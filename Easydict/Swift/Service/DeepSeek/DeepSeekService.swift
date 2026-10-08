//
//  DeepSeekService.swift
//  Easydict
//
//  Created by GarethNg on 2025/2/19.
//  Copyright © 2025 izual. All rights reserved.
//

import Defaults
import Foundation

// MARK: - DeepSeekService

/// DeepSeek translation service. Layers DeepSeek V4 reasoning parameters
/// (`thinking.type` and `reasoning_effort`) on top of the OpenAI-compatible
/// streaming pipeline as a model-agnostic per-service setting, so current
/// and future DeepSeek models opt in without code changes.
@objc(EZDeepSeekService)
class DeepSeekService: OpenAIService {
    // MARK: Public

    public override func cancelStream() {
        currentTask?.cancel()
    }

    public override func name() -> String {
        NSLocalizedString("deepseek_translate", comment: "")
    }

    public override func serviceType() -> ServiceType {
        .deepSeek
    }

    public override func link() -> String? {
        "https://www.deepseek.com/"
    }

    // MARK: Internal

    override var defaultModels: [String] {
        DeepSeekModel.allCases.map(\.rawValue)
    }

    override var defaultModel: String {
        DeepSeekModel.deepseekV4Flash.rawValue
    }

    override var observeKeys: [Defaults.Key<String>] {
        [apiKeyKey, supportedModelsKey]
    }

    override var defaultEndpoint: String {
        "https://api.deepseek.com/v1/chat/completions"
    }

    /// DeepSeek V4 supports reasoning effort, exposing the shared picker and
    /// sending `thinking` and `reasoning_effort` to the API.
    override var supportsReasoningEffort: Bool {
        true
    }

    /// DeepSeek is often pointed at company gateways that also host other
    /// vendors' models in their native formats.
    override var supportsModelProtocolRouting: Bool {
        true
    }

    /// Only DeepSeek's own host uses the documented `/models` URL. A custom
    /// endpoint, such as a company gateway, lists its own models, so the
    /// request must go to that host instead of api.deepseek.com.
    override func remoteModelsEndpoint(forChatEndpoint chatEndpoint: String) -> String? {
        let host = URL(string: chatEndpoint.trim())?.host?.lowercased()
        return host == "api.deepseek.com" ? "https://api.deepseek.com/models" : nil
    }

    override func contentStreamTranslate(
        _ text: String,
        from: Language,
        to: Language
    )
        -> AsyncThrowingStream<String, Error> {
        // A custom endpoint may serve some models only in their native format.
        let apiProtocol = resolvedModelProtocol()
        if apiProtocol != .openAIChat, !apiKey.isEmpty {
            return modelProtocolContentStream(apiProtocol, text: text, from: from, to: to)
        }

        return AsyncThrowingStream { continuation in
            guard let url = URL(string: endpoint), url.isValid else {
                continuation.finish(
                    throwing: QueryError(
                        type: .parameter,
                        message: "`\(serviceType().rawValue)` endpoint is invalid"
                    )
                )
                return
            }

            guard !apiKey.isEmpty else {
                continuation.finish(
                    throwing: QueryError(type: .missingSecretKey, message: "API key is empty")
                )
                return
            }

            if let currentTask, !currentTask.isCancelled {
                currentTask.cancel()
            }

            let task = Task {
                do {
                    let queryType = queryType(text: text, from: from, to: to)
                    let chatQueryParam = ChatQueryParam(
                        text: text,
                        sourceLanguage: from,
                        targetLanguage: to,
                        queryType: queryType,
                        enableSystemPrompt: true
                    )
                    let request = try makeChatRequest(
                        url: url,
                        messages: chatMessageDicts(chatQueryParam)
                    )

                    let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
                    try await validateHTTPResponse(response, body: asyncBytes)
                    try await processStreamBytes(asyncBytes, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    logInfo("DeepSeek task was cancelled.")
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            currentTask = task
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: Private

    private var currentTask: Task<(), Never>?

    private func makeChatRequest(url: URL, messages: [ChatMessage]) throws -> URLRequest {
        let effort = reasoningEffort
        let requestBody = DeepSeekChatRequest(
            messages: messages.map(DeepSeekChatMessage.init),
            model: model,
            temperature: temperature,
            stream: true,
            thinking: .init(type: effort.isEnabled ? "enabled" : "disabled"),
            reasoningEffort: effort.requestValue
        )

        var request = URLRequest(url: url, timeoutInterval: EZNetWorkTimeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }

    /// Throws for non-2xx responses, surfacing the API's error message (for
    /// example a model rejecting image input) instead of a bare status code.
    private func validateHTTPResponse(
        _ response: URLResponse,
        body: URLSession.AsyncBytes
    ) async throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QueryError(type: .api, message: "Invalid DeepSeek response")
        }

        let statusCode = httpResponse.statusCode
        guard (200 ... 299).contains(statusCode) else {
            var data = Data()
            let maxErrorBodyLength = 64 * 1024
            for try await byte in body {
                data.append(byte)
                if data.count >= maxErrorBodyLength { break }
            }

            let apiMessage = (try? JSONDecoder().decode(DeepSeekErrorResponse.self, from: data))?
                .error?.message?.trim()
            let bodyText = String(data: data, encoding: .utf8)?.trim()
            throw QueryError(
                type: .api,
                message: "HTTP \(statusCode)",
                errorDataMessage: apiMessage ?? bodyText.map { String($0.prefix(300)) }
            )
        }
    }

    private func processStreamBytes(
        _ asyncBytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        var dataBuffer = Data()
        var textBuffer = ""

        for try await byte in asyncBytes {
            try Task.checkCancellation()
            dataBuffer.append(byte)

            guard byte == 0x0A else {
                continue
            }

            if let text = String(data: dataBuffer, encoding: .utf8) {
                textBuffer.append(text)
                dataBuffer.removeAll()
                processCompleteEvents(from: &textBuffer, continuation: continuation)
            }
        }

        if !dataBuffer.isEmpty, let text = String(data: dataBuffer, encoding: .utf8) {
            textBuffer.append(text)
        }
        processCompleteEvents(from: &textBuffer, continuation: continuation)
    }

    private func processCompleteEvents(
        from textBuffer: inout String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) {
        textBuffer = textBuffer.replacingOccurrences(of: "\r\n", with: "\n")
        let eventSeparator = "\n\n"
        guard textBuffer.contains(eventSeparator) else { return }

        let parts = textBuffer.split(separator: eventSeparator, omittingEmptySubsequences: false)
        textBuffer = String(parts.last ?? "")

        for event in parts.dropLast() where !event.isEmpty {
            guard let content = parseSSEEvent(String(event)) else { continue }
            continuation.yield(content)
        }
    }

    private func parseSSEEvent(_ event: String) -> String? {
        let dataPrefix = "data:"
        let doneFlag = "[DONE]"
        var dataString = ""

        for line in event.split(separator: "\n") where line.starts(with: dataPrefix) {
            let payload = line.dropFirst(dataPrefix.count).trimmingCharacters(in: .whitespaces)
            guard payload != doneFlag else { return nil }
            dataString += payload
        }

        guard !dataString.isEmpty,
              let data = dataString.data(using: .utf8)
        else {
            return nil
        }

        guard let chunk = try? JSONDecoder().decode(DeepSeekStreamChunk.self, from: data) else {
            logError("Failed to decode DeepSeek SSE data: \(dataString)")
            return nil
        }

        return chunk.choices.first?.delta.content
    }
}

// MARK: - DeepSeekModel

enum DeepSeekModel: String, CaseIterable {
    // Docs: https://api-docs.deepseek.com
    // Pricing: https://api-docs.deepseek.com/quick_start/pricing
    case deepseekV4Flash = "deepseek-v4-flash"
    case deepseekV4Pro = "deepseek-v4-pro"
}

// MARK: - DeepSeekChatRequest

/// Encodable chat-completions payload for DeepSeek. Mirrors the OpenAI-
/// compatible fields Easydict already uses and adds DeepSeek V4's `thinking`
/// and `reasoning_effort` parameters.
private struct DeepSeekChatRequest: Encodable {
    // MARK: Internal

    let messages: [DeepSeekChatMessage]
    let model: String
    let temperature: Double
    let stream: Bool
    let thinking: DeepSeekThinking
    let reasoningEffort: String?

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case messages
        case model
        case temperature
        case stream
        case thinking
        case reasoningEffort = "reasoning_effort"
    }
}

// MARK: - DeepSeekChatMessage

/// Minimal chat message shape accepted by DeepSeek's OpenAI-compatible
/// endpoint, built from Easydict's provider-agnostic prompt messages. User
/// messages with images encode `content` as OpenAI-style content parts.
private struct DeepSeekChatMessage: Encodable {
    // MARK: Lifecycle

    init(_ message: ChatMessage) {
        self.role = message.role.rawValue
        self.content = message.content
        self.imageURLs = message.imageURLs
    }

    // MARK: Internal

    let role: String
    let content: String
    let imageURLs: [String]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)

        if imageURLs.isEmpty {
            try container.encode(content, forKey: .content)
            return
        }

        var parts: [DeepSeekContentPart] = []
        if !content.isEmpty {
            parts.append(.text(content))
        }
        parts += imageURLs.map { .imageURL($0) }
        try container.encode(parts, forKey: .content)
    }

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case role
        case content
    }
}

// MARK: - DeepSeekContentPart

/// One OpenAI-style content part: a text block or an `image_url` reference.
private enum DeepSeekContentPart: Encodable {
    case text(String)
    case imageURL(String)

    // MARK: Internal

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .imageURL(url):
            try container.encode("image_url", forKey: .type)
            try container.encode(["url": url], forKey: .imageURL)
        }
    }

    // MARK: Private

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

// MARK: - DeepSeekErrorResponse

/// Error body returned by DeepSeek's OpenAI-compatible endpoint.
private struct DeepSeekErrorResponse: Decodable {
    struct Detail: Decodable {
        let message: String?
    }

    let error: Detail?
}

// MARK: - DeepSeekThinking

/// DeepSeek V4 thinking mode switch. The effort level is encoded separately
/// because the API keeps `thinking.type` and `reasoning_effort` as sibling
/// parameters.
private struct DeepSeekThinking: Encodable {
    let type: String
}

// MARK: - DeepSeekStreamChunk

/// Streaming chat-completions chunk returned by DeepSeek. Only the assistant
/// content delta is needed for Easydict's text output pipeline.
private struct DeepSeekStreamChunk: Decodable {
    struct Choice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }

    let choices: [Choice]
}
