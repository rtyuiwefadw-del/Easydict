//
//  StreamService+ModelProtocol.swift
//  Easydict
//
//  Created by wangjiapeng on 2026/10/8.
//  Copyright © 2026 izual. All rights reserved.
//

import Defaults
import Foundation

// MARK: - StreamService + ModelProtocol

extension StreamService {
    /// User rules mapping model names to protocols, one `pattern=protocol` per line.
    var modelProtocolRulesKey: Defaults.Key<String> {
        stringDefaultsKey(.modelProtocolRules, defaultValue: "")
    }

    /// Protocol for the current model, or OpenAI Chat Completions when the
    /// service does not route by model name.
    func resolvedModelProtocol() -> ModelAPIProtocol {
        guard supportsModelProtocolRouting else { return .openAIChat }
        let rules = ModelProtocolRule.parse(Defaults[modelProtocolRulesKey])
        return ModelAPIProtocol.resolve(model: model, rules: rules)
    }

    /// Streams the answer for a query in a native vendor format, building the
    /// same conversation-aware messages as the OpenAI-compatible path.
    func modelProtocolContentStream(
        _ apiProtocol: ModelAPIProtocol,
        text: String,
        from: Language,
        to: Language
    )
        -> AsyncThrowingStream<String, Error> {
        let chatQuery = ChatQueryParam(
            text: text,
            sourceLanguage: from,
            targetLanguage: to,
            queryType: queryType(text: text, from: from, to: to),
            enableSystemPrompt: true
        )
        let builder = ModelAPIRequestBuilder(
            chatEndpoint: endpoint,
            apiKey: apiKey.trim(),
            model: model,
            temperature: temperature
        )
        return streamModelAPI(apiProtocol, builder: builder, messages: chatMessageDicts(chatQuery))
    }

    /// Sends one streaming request and yields text deltas parsed from its
    /// server-sent events. Non-2xx responses throw with the server's message.
    func streamModelAPI(
        _ apiProtocol: ModelAPIProtocol,
        builder: ModelAPIRequestBuilder,
        messages: [ChatMessage]
    )
        -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try builder.request(for: apiProtocol, messages: messages)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    try await validateModelAPIResponse(response, body: bytes)

                    var lineBuffer = Data()
                    var textBuffer = ""
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        lineBuffer.append(byte)
                        guard byte == 0x0A, let line = String(data: lineBuffer, encoding: .utf8) else {
                            continue
                        }
                        lineBuffer.removeAll()
                        textBuffer += line

                        let (events, remaining) = ClaudeSSEParser.extractCompleteEvents(from: textBuffer)
                        textBuffer = remaining
                        for event in events {
                            if let delta = try ModelAPIStreamParser.textDelta(in: event, for: apiProtocol) {
                                continuation.yield(delta)
                            }
                        }
                    }

                    // A stream may end without the blank line after its last event.
                    textBuffer += String(decoding: lineBuffer, as: UTF8.self)
                    let lastEvent = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !lastEvent.isEmpty,
                       let delta = try ModelAPIStreamParser.textDelta(in: lastEvent, for: apiProtocol) {
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: Private

    private func validateModelAPIResponse(_ response: URLResponse, body: URLSession.AsyncBytes) async throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw QueryError(type: .api, message: "Invalid response")
        }

        let statusCode = httpResponse.statusCode
        guard (200 ... 299).contains(statusCode) else {
            var data = Data()
            for try await byte in body {
                data.append(byte)
                if data.count >= 64 * 1024 { break }
            }
            throw QueryError(
                type: .api,
                message: "HTTP \(statusCode)",
                errorDataMessage: ModelAPIStreamParser.errorMessage(from: data)
            )
        }
    }
}
