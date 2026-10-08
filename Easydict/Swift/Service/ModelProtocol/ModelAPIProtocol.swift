//
//  ModelAPIProtocol.swift
//  Easydict
//
//  Created by wangjiapeng on 2026/10/8.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation

// MARK: - ModelAPIProtocol

/// Wire format used to talk to a model. Gateways that serve several vendors at
/// one address often keep each vendor's native API, so the format is picked
/// per model name: user rules first, then well-known name prefixes.
enum ModelAPIProtocol: String, CaseIterable {
    /// OpenAI Chat Completions: `POST …/v1/chat/completions`.
    case openAIChat = "openai"
    /// Anthropic Messages: `POST …/v1/messages`.
    case anthropicMessages = "anthropic"
    /// Google Gemini: `POST …/v1beta/models/{model}:streamGenerateContent`.
    case geminiGenerateContent = "gemini"
    /// OpenAI Responses: `POST …/v1/responses`.
    case openAIResponses = "responses"

    // MARK: Internal

    /// Picks the protocol for `model`. The first matching rule wins; without
    /// a match, `claude*` uses Anthropic, `gemini*` uses Gemini, and anything
    /// else uses OpenAI Chat Completions.
    static func resolve(model: String, rules: [ModelProtocolRule] = []) -> Self {
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let rule = rules.first(where: { $0.matches(name) }) {
            return rule.apiProtocol
        }

        // Gateways often namespace models, such as `anthropic/claude-sonnet-4`.
        let baseName = name.split(separator: "/").last.map(String.init) ?? name
        if baseName.hasPrefix("claude") {
            return .anthropicMessages
        }
        if baseName.hasPrefix("gemini") {
            return .geminiGenerateContent
        }
        return .openAIChat
    }
}

// MARK: - ModelProtocolRule

/// One user rule mapping model names to a protocol, written as
/// `pattern=protocol` (for example `gpt-5*=responses`). A trailing `*`
/// matches any suffix; otherwise the whole name must match. Case-insensitive.
struct ModelProtocolRule: Equatable {
    let pattern: String
    let apiProtocol: ModelAPIProtocol

    /// Parses one rule per line, ignoring blank lines, `#` comments, and lines
    /// with an unknown protocol name, so a typo never breaks other rules.
    static func parse(_ text: String) -> [ModelProtocolRule] {
        text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let separator = trimmed.firstIndex(of: "=")
            else {
                return nil
            }

            let pattern = trimmed[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let protocolName = trimmed[trimmed.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces).lowercased()
            guard !pattern.isEmpty, let apiProtocol = ModelAPIProtocol(rawValue: protocolName) else {
                return nil
            }
            return ModelProtocolRule(pattern: pattern, apiProtocol: apiProtocol)
        }
    }

    /// Whether `modelName` (already lowercased) matches this rule.
    func matches(_ modelName: String) -> Bool {
        if pattern.hasSuffix("*") {
            return modelName.hasPrefix(String(pattern.dropLast()))
        }
        return modelName == pattern
    }
}
