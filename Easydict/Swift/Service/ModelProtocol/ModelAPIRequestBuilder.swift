//
//  ModelAPIRequestBuilder.swift
//  Easydict
//
//  Created by wangjiapeng on 2026/10/8.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation

// MARK: - ModelAPIRequestBuilder

/// Builds streaming requests in each vendor's native format from the chat
/// endpoint a user configured. The site prefix is taken from that endpoint,
/// so one gateway address serves every protocol; messages keep conversation
/// history and images, encoded the way each vendor expects.
struct ModelAPIRequestBuilder {
    // MARK: Internal

    /// Anthropic API version sent with every Messages request.
    static let anthropicVersion = "2023-06-01"

    /// Output token cap; Anthropic requires `max_tokens` on every request.
    static let anthropicMaxTokens = 8192

    let chatEndpoint: String
    let apiKey: String
    let model: String
    let temperature: Double

    /// Builds a streaming request for `apiProtocol`. OpenAI Chat Completions
    /// is sent by the existing OpenAI-compatible path, so it is rejected here.
    func request(for apiProtocol: ModelAPIProtocol, messages: [ChatMessage]) throws -> URLRequest {
        var request = URLRequest(url: try url(for: apiProtocol), timeoutInterval: EZNetWorkTimeoutInterval)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (name, value) in headers(for: apiProtocol) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = try JSONSerialization.data(
            withJSONObject: body(for: apiProtocol, messages: messages),
            options: [.sortedKeys]
        )
        return request
    }

    /// Request URL for `apiProtocol`, built on the site prefix of the chat endpoint.
    func url(for apiProtocol: ModelAPIProtocol) throws -> URL {
        let prefix = try sitePrefix()
        let urlString: String
        switch apiProtocol {
        case .openAIChat:
            urlString = chatEndpoint.trim()
        case .anthropicMessages:
            urlString = prefix + "/v1/messages"
        case .geminiGenerateContent:
            let modelPath = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            urlString = prefix + "/v1beta/models/\(modelPath):streamGenerateContent?alt=sse"
        case .openAIResponses:
            urlString = prefix + "/v1/responses"
        }

        guard let url = URL(string: urlString), url.isValid else {
            throw QueryError(type: .parameter, message: "Endpoint is invalid")
        }
        return url
    }

    /// The endpoint without its API path, such as `https://gw.example.com/api`
    /// for `https://gw.example.com/api/v1/chat/completions`. Endpoints already
    /// pointing at Messages or Responses are trimmed the same way.
    func sitePrefix() throws -> String {
        guard var components = URLComponents(string: chatEndpoint.trim()),
              let scheme = components.scheme, ["http", "https"].contains(scheme.lowercased()),
              components.host?.isEmpty == false
        else {
            throw QueryError(type: .parameter, message: "Endpoint is invalid")
        }

        var parts = components.path.split(separator: "/").map(String.init)
        let lowercasedParts = parts.map { $0.lowercased() }
        if Array(lowercasedParts.suffix(2)) == ["chat", "completions"] {
            parts.removeLast(2)
        } else if let last = lowercasedParts.last, ["completions", "messages", "responses"].contains(last) {
            parts.removeLast()
        }
        if parts.last?.lowercased() == "v1" {
            parts.removeLast()
        }

        components.path = parts.isEmpty ? "" : "/" + parts.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        guard let prefix = components.string else {
            throw QueryError(type: .parameter, message: "Endpoint is invalid")
        }
        return prefix
    }

    /// Authentication headers. Native headers come first; Bearer is added too
    /// because many gateways authenticate every protocol that way.
    func headers(for apiProtocol: ModelAPIProtocol) -> [(String, String)] {
        let bearer = ("Authorization", "Bearer \(apiKey)")
        switch apiProtocol {
        case .anthropicMessages:
            return [("x-api-key", apiKey), ("anthropic-version", Self.anthropicVersion), bearer]
        case .geminiGenerateContent:
            return [("x-goog-api-key", apiKey), bearer]
        case .openAIChat, .openAIResponses:
            return [bearer]
        }
    }

    /// JSON body for `apiProtocol`.
    func body(for apiProtocol: ModelAPIProtocol, messages: [ChatMessage]) throws -> [String: Any] {
        switch apiProtocol {
        case .openAIChat:
            throw QueryError(type: .parameter, message: "OpenAI Chat Completions uses the OpenAI-compatible path")
        case .anthropicMessages:
            return anthropicBody(messages)
        case .geminiGenerateContent:
            return geminiBody(messages)
        case .openAIResponses:
            return responsesBody(messages)
        }
    }

    // MARK: Private

    /// Base64 image parsed from a `data:<media type>;base64,<data>` URL.
    private struct InlineImage {
        // MARK: Lifecycle

        init?(dataURL: String) {
            guard dataURL.hasPrefix("data:"),
                  let comma = dataURL.firstIndex(of: ",")
            else {
                return nil
            }
            let header = dataURL[dataURL.index(dataURL.startIndex, offsetBy: 5) ..< comma]
            self.mediaType = header.split(separator: ";").first.map(String.init) ?? "image/jpeg"
            self.base64 = String(dataURL[dataURL.index(after: comma)...])
        }

        // MARK: Internal

        let mediaType: String
        let base64: String
    }

    private func systemText(_ messages: [ChatMessage]) -> String {
        messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
    }

    private func conversation(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { $0.role != .system }
    }

    private func isAssistant(_ message: ChatMessage) -> Bool {
        message.role == .assistant || message.role == .model
    }

    private func anthropicBody(_ messages: [ChatMessage]) -> [String: Any] {
        let turns: [[String: Any]] = conversation(messages).map { message in
            let role = isAssistant(message) ? "assistant" : "user"
            let images = message.imageURLs.compactMap(InlineImage.init(dataURL:))
            guard !images.isEmpty else {
                return ["role": role, "content": message.content]
            }

            var blocks: [[String: Any]] = images.map { image in
                [
                    "type": "image",
                    "source": ["type": "base64", "media_type": image.mediaType, "data": image.base64],
                ]
            }
            if !message.content.isEmpty {
                blocks.append(["type": "text", "text": message.content])
            }
            return ["role": role, "content": blocks]
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": Self.anthropicMaxTokens,
            "stream": true,
            // Anthropic accepts temperatures from 0 to 1.
            "temperature": min(max(temperature, 0), 1),
            "messages": turns,
        ]
        let system = systemText(messages)
        if !system.isEmpty {
            body["system"] = system
        }
        return body
    }

    private func geminiBody(_ messages: [ChatMessage]) -> [String: Any] {
        let contents: [[String: Any]] = conversation(messages).map { message in
            var parts: [[String: Any]] = []
            if !message.content.isEmpty {
                parts.append(["text": message.content])
            }
            for image in message.imageURLs.compactMap(InlineImage.init(dataURL:)) {
                parts.append(["inline_data": ["mime_type": image.mediaType, "data": image.base64]])
            }
            return ["role": isAssistant(message) ? "model" : "user", "parts": parts]
        }

        var body: [String: Any] = [
            "contents": contents,
            "generationConfig": ["temperature": temperature],
        ]
        let system = systemText(messages)
        if !system.isEmpty {
            body["systemInstruction"] = ["parts": [["text": system]]]
        }
        return body
    }

    private func responsesBody(_ messages: [ChatMessage]) -> [String: Any] {
        let input: [[String: Any]] = conversation(messages).map { message in
            if isAssistant(message) {
                return ["role": "assistant", "content": [["type": "output_text", "text": message.content]]]
            }

            var content: [[String: Any]] = []
            if !message.content.isEmpty {
                content.append(["type": "input_text", "text": message.content])
            }
            for url in message.imageURLs {
                content.append(["type": "input_image", "image_url": url])
            }
            return ["role": "user", "content": content]
        }

        // Reasoning models on the Responses API reject `temperature`, so it is
        // left to the server default.
        var body: [String: Any] = ["model": model, "stream": true, "input": input]
        let system = systemText(messages)
        if !system.isEmpty {
            body["instructions"] = system
        }
        return body
    }
}
