//
//  ConversationTurnTests.swift
//  EasydictTests
//
//  Created by wangjiapeng on 2026/9/28.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import OpenAI
import Testing

@testable import Easydict

// MARK: - ConversationTurnTests

/// Behavior tests for AI follow-up conversations and image questions on
/// ``StreamService``. They cover which messages each turn sends, how finished
/// answers become follow-up context, the transcript shown in the result card,
/// and how attached images are encoded for OpenAI-compatible requests.
@Suite("Conversation Turn", .tags(.unit))
struct ConversationTurnTests {
    // MARK: Internal

    @Test("A plain new query keeps the regular translation prompts")
    func plainQueryUsesRegularPrompts() {
        let service = makeService()
        let turn = service.beginConversationTurn(question: "Hello")

        #expect(!turn.isFollowUp)
        #expect(turn.transcriptPrefix.isEmpty)
        #expect(service.conversationTurnMessages(chatQuery("Hello")) == nil)
    }

    @Test("An image question uses an assistant prompt with image parts")
    func imageQuestionUsesAssistantPrompt() {
        let service = makeService(images: [makeImage(width: 40, height: 20)])
        _ = service.beginConversationTurn(question: "What is this?")

        let messages = service.conversationTurnMessages(chatQuery("What is this?"))
        #expect(messages?.count == 2)
        #expect(messages?.first?.role == .system)
        #expect(messages?.last?.role == .user)
        #expect(messages?.last?.content == "What is this?")
        #expect(messages?.last?.imageURLs.count == 1)
        #expect(messages?.last?.imageURLs.first?.hasPrefix("data:image/jpeg;base64,") == true)
    }

    @Test("A finished answer becomes context for the next follow-up")
    func followUpContinuesPreviousExchange() {
        let service = makeService()
        _ = service.beginConversationTurn(question: "Hello")
        service.lastRequestMessages = [.init(role: .user, content: "Hello")]
        service.finishConversationTurn(answer: "你好", transcript: "你好")

        #expect(service.canFollowUp)

        service.isFollowUpPending = true
        let turn = service.beginConversationTurn(question: "Why?")
        #expect(turn.isFollowUp)
        #expect(!service.isFollowUpPending)

        let messages = service.conversationTurnMessages(chatQuery("Why?")) ?? []
        #expect(messages.map(\.role) == [.user, .assistant, .user])
        #expect(messages.map(\.content) == ["Hello", "你好", "Why?"])
    }

    @Test("A pending follow-up without a finished answer starts over")
    func followUpWithoutContextStartsNewConversation() {
        let service = makeService()
        service.isFollowUpPending = true

        let turn = service.beginConversationTurn(question: "Why?")
        #expect(!turn.isFollowUp)
        #expect(!service.canFollowUp)
    }

    @Test("Resetting results drops a follow-up flag that never streamed")
    func resetClearsPendingFollowUp() {
        let service = makeService()
        service.conversationMessages = [.init(role: .user, content: "Hello")]
        service.isFollowUpPending = true

        service.resetServiceResult()
        let turn = service.beginConversationTurn(question: "New")
        #expect(!turn.isFollowUp)
    }

    @Test("A regular query clears the previous conversation")
    func regularQueryResetsConversation() {
        let service = makeService()
        service.conversationMessages = [.init(role: .user, content: "Old")]
        service.conversationTranscript = "Old answer"

        _ = service.beginConversationTurn(question: "New")
        #expect(service.conversationMessages.isEmpty)
        #expect(service.conversationTranscript.isEmpty)
    }

    @Test("Follow-up transcript quotes the question under a divider")
    func followUpTranscriptPrefix() {
        let service = makeService()
        let prefix = service.followUpTranscriptPrefix(
            previousTranscript: "First answer\n",
            question: "Line one\nLine two",
            imageCount: 0
        )

        #expect(prefix.hasPrefix("First answer\n\n---\n\n"))
        #expect(prefix.contains("> Line one\n> Line two"))
        #expect(prefix.hasSuffix("\n\n"))
    }

    @Test("Large images are scaled down before encoding")
    func imageDataURLIsScaledDown() throws {
        let image = makeImage(width: 4000, height: 1000)
        let dataURL = try #require(image.chatImageDataURL(maxPixelSize: 2048))

        let base64 = String(dataURL.dropFirst("data:image/jpeg;base64,".count))
        let data = try #require(Data(base64Encoded: base64))
        let bitmap = try #require(NSBitmapImageRep(data: data))
        #expect(bitmap.pixelsWide == 2048)
        #expect(bitmap.pixelsHigh == 512)
    }

    @Test("OpenAI-compatible requests encode images as image_url parts")
    func visionMessageEncoding() throws {
        let service = makeService()
        let message = service.visionUserMessage(
            text: "Describe",
            imageURLs: ["data:image/jpeg;base64,AAAA"]
        )

        let data = try JSONEncoder().encode(message)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"image_url\""))
        #expect(json.contains("data:image\\/jpeg;base64,AAAA") || json.contains("data:image/jpeg;base64,AAAA"))
        #expect(json.contains("\"Describe\""))
    }

    // MARK: Private

    private func makeService(images: [NSImage] = []) -> OpenAIService {
        let service = OpenAIService()
        let model = QueryModel()
        model.attachedImages = images
        service.queryModel = model
        return service
    }

    private func chatQuery(_ text: String) -> ChatQueryParam {
        ChatQueryParam(
            text: text,
            sourceLanguage: .english,
            targetLanguage: .simplifiedChinese,
            queryType: .translation,
            enableSystemPrompt: true
        )
    }

    private func makeImage(width: Int, height: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        if let bitmap {
            image.addRepresentation(bitmap)
        }
        return image
    }
}
