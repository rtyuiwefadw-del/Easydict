//
//  ModelAPIStreamParser.swift
//  Easydict
//
//  Created by wangjiapeng on 2026/10/8.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation

// MARK: - ModelAPIStreamParser

/// Extracts answer text from one server-sent event of a native vendor stream,
/// and readable messages from error bodies. Payloads are read as loose JSON
/// because gateways often add or drop fields around the vendor format.
enum ModelAPIStreamParser {
    // MARK: Internal

    /// Text delta in `event` for `apiProtocol`, or `nil` for events without text.
    /// Throws when the event reports a stream error.
    static func textDelta(in event: String, for apiProtocol: ModelAPIProtocol) throws -> String? {
        switch apiProtocol {
        case .anthropicMessages:
            return try ClaudeSSEParser.parseEvent(event)
        case .geminiGenerateContent:
            return try geminiText(in: event)
        case .openAIResponses:
            return try responsesText(in: event)
        case .openAIChat:
            return nil
        }
    }

    /// Human-readable message from an error response body, such as
    /// `{"error":{"message":…}}`, `{"error":"…"}`, `{"message":…}`, or a
    /// Gemini-style array; falls back to the first 300 characters of text.
    static func errorMessage(from data: Data) -> String? {
        if let json = try? JSONSerialization.jsonObject(with: data) {
            let object = (json as? [Any])?.first ?? json
            if let message = message(in: object) {
                return message
            }
        }

        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(300))
    }

    // MARK: Private

    /// The `event:` name and the joined `data:` payload of one SSE event.
    private static func fields(of event: String) -> (name: String?, data: String) {
        var name: String?
        var dataLines: [String] = []
        for line in event.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("event:") {
                name = trimmed.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("data:") {
                dataLines.append(trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces))
            }
        }
        return (name, dataLines.joined(separator: "\n"))
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        guard !text.isEmpty, text != "[DONE]", let data = text.data(using: .utf8) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func geminiText(in event: String) throws -> String? {
        guard let payload = jsonObject(fields(of: event).data) else { return nil }

        if payload["error"] != nil {
            throw QueryError(type: .api, errorDataMessage: message(in: payload))
        }

        let candidates = payload["candidates"] as? [[String: Any]] ?? []
        let parts = (candidates.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        // Thinking models stream their reasoning as parts marked `thought`.
        let text = parts.filter { ($0["thought"] as? Bool) != true }
            .compactMap { $0["text"] as? String }
            .joined()
        return text.isEmpty ? nil : text
    }

    private static func responsesText(in event: String) throws -> String? {
        let (name, data) = fields(of: event)
        guard let payload = jsonObject(data) else { return nil }

        let type = payload["type"] as? String ?? name
        switch type {
        case "response.output_text.delta":
            return payload["delta"] as? String
        case "error", "response.failed":
            let response = payload["response"] as? [String: Any]
            throw QueryError(type: .api, errorDataMessage: message(in: response ?? payload))
        default:
            return nil
        }
    }

    /// Finds an error message in common error payload shapes.
    private static func message(in object: Any) -> String? {
        guard let dictionary = object as? [String: Any] else { return nil }

        if let error = dictionary["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let error = dictionary["error"] as? String {
            return error
        }
        return dictionary["message"] as? String
    }
}
