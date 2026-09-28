//
//  StreamService+Conversation.swift
//  Easydict
//
//  Created by wangjiapeng on 2026/9/28.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Foundation

// MARK: - ConversationTurn

/// Snapshot of one request in an AI conversation: the earlier messages it
/// continues, the transcript shown above its answer, and the images attached
/// to its question. Captured when a stream starts so later UI changes, such
/// as clearing the input box, cannot alter the request in flight.
struct ConversationTurn {
    /// Messages of the previous exchange; empty when the turn starts a new chat.
    let context: [ChatMessage]

    /// Markdown shown before the streamed answer in the result card.
    let transcriptPrefix: String

    /// Images attached to this turn's question, encoded as `data:` URLs.
    let imageURLs: [String]

    var isFollowUp: Bool {
        !context.isEmpty
    }
}

// MARK: - StreamService + Conversation

extension StreamService {
    /// Generic system prompt for questions that are not translations, such as
    /// image questions without a custom system prompt.
    static let assistantSystemPrompt = """
    You are a helpful assistant. Answer accurately and concisely. When the user shares an image, read it carefully, including any text in it.
    """

    /// Starts a request turn. A pending follow-up continues the previous
    /// exchange; any other request starts a new conversation.
    func beginConversationTurn(question: String) -> ConversationTurn {
        let isFollowUp = isFollowUpPending && !conversationMessages.isEmpty
        isFollowUpPending = false

        let imageURLs = queryModel.attachedImages.compactMap { $0.chatImageDataURL() }

        let turn: ConversationTurn
        if isFollowUp {
            turn = ConversationTurn(
                context: conversationMessages,
                transcriptPrefix: followUpTranscriptPrefix(
                    previousTranscript: conversationTranscript,
                    question: question,
                    imageCount: imageURLs.count
                ),
                imageURLs: imageURLs
            )
        } else {
            conversationMessages = []
            conversationTranscript = ""
            turn = ConversationTurn(context: [], transcriptPrefix: "", imageURLs: imageURLs)
        }

        activeConversationTurn = turn
        lastRequestMessages = []
        return turn
    }

    /// Records a successful answer so the next follow-up can continue it.
    func finishConversationTurn(answer: String, transcript: String) {
        guard !answer.isEmpty, !lastRequestMessages.isEmpty else { return }

        conversationMessages = lastRequestMessages + [.init(role: .assistant, content: answer)]
        conversationTranscript = transcript
        activeConversationTurn = nil
    }

    /// Messages for follow-up or image turns, or `nil` to use the regular
    /// translation, sentence, or dictionary prompts.
    func conversationTurnMessages(_ chatQuery: ChatQueryParam) -> [ChatMessage]? {
        guard let turn = activeConversationTurn else { return nil }

        if turn.isFollowUp {
            return turn.context + [
                .init(role: .user, content: chatQuery.text, imageURLs: turn.imageURLs),
            ]
        }

        guard !turn.imageURLs.isEmpty else { return nil }

        var messages: [ChatMessage] = []
        let customSystemPrompt = enableCustomPrompt ? replaceCustomPromptWithVariable(systemPrompt) : ""
        let systemContent = customSystemPrompt.isEmpty ? Self.assistantSystemPrompt : customSystemPrompt
        messages.append(.init(role: .system, content: systemContent))
        messages.append(.init(role: .user, content: chatQuery.text, imageURLs: turn.imageURLs))
        return messages
    }

    /// Builds the Markdown shown above a follow-up answer: the previous
    /// transcript, a divider, and the new question as a quote.
    func followUpTranscriptPrefix(
        previousTranscript: String,
        question: String,
        imageCount: Int
    )
        -> String {
        var quoteLines = question.trim()
            .components(separatedBy: .newlines)
            .map { "> \($0)" }
        if imageCount > 0 {
            let imageNote = String(
                format: String(localized: "conversation.transcript.image_count"),
                imageCount
            )
            quoteLines.append("> \(imageNote)")
        }

        let title = String(localized: "conversation.transcript.follow_up_title")
        return previousTranscript.trim()
            + "\n\n---\n\n**\(title)**\n\n"
            + quoteLines.joined(separator: "\n")
            + "\n\n"
    }
}

// MARK: - NSImage + Chat

extension NSImage {
    /// Encodes the image as a JPEG `data:` URL for chat requests, scaling the
    /// longer side down to `maxPixelSize` and flattening transparency onto
    /// white so screenshots stay legible and requests stay small.
    func chatImageDataURL(maxPixelSize: CGFloat = 2048, compression: Double = 0.85) -> String? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return nil }

        let scale = min(1, maxPixelSize / max(width, height))
        let targetWidth = max(1, Int((width * scale).rounded()))
        let targetHeight = max(1, Int((height * scale).rounded()))

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: targetWidth,
                  height: targetHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        context.interpolationQuality = .high
        context.draw(cgImage, in: rect)

        guard let flattenedImage = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: flattenedImage)
              .representation(using: .jpeg, properties: [.compressionFactor: compression])
        else {
            return nil
        }

        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }
}
