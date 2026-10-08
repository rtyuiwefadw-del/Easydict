//
//  ModelProtocolTests.swift
//  EasydictTests
//
//  Created by wangjiapeng on 2026/10/8.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation
import Testing

@testable import Easydict

// MARK: - ModelProtocolTests

/// Tests for picking an API format per model name on a multi-vendor gateway:
/// detection and user rules, request URLs, headers and bodies for Anthropic,
/// Gemini, and Responses, stream parsing, and end-to-end streaming against a
/// local server that stands in for the gateway.
@Suite("Model Protocol Routing", .tags(.unit))
struct ModelProtocolTests {
    // MARK: Internal

    // MARK: Detection and rules

    @Test("Model names pick a protocol by vendor prefix")
    func detectsProtocolFromModelName() {
        #expect(ModelAPIProtocol.resolve(model: "claude-sonnet-4-5") == .anthropicMessages)
        #expect(ModelAPIProtocol.resolve(model: "anthropic/Claude-Opus-4") == .anthropicMessages)
        #expect(ModelAPIProtocol.resolve(model: "gemini-2.5-pro") == .geminiGenerateContent)
        #expect(ModelAPIProtocol.resolve(model: "deepseek-v4-flash") == .openAIChat)
        #expect(ModelAPIProtocol.resolve(model: "qwen3-coder") == .openAIChat)
    }

    @Test("User rules override detection and skip invalid lines")
    func rulesOverrideDetection() {
        let rules = ModelProtocolRule.parse("""
        # company gateway
        gpt-5*=responses
        claude-internal = openai

        broken line
        foo=unknown-format
        """)

        #expect(rules.count == 2)
        #expect(ModelAPIProtocol.resolve(model: "gpt-5-mini", rules: rules) == .openAIResponses)
        #expect(ModelAPIProtocol.resolve(model: "Claude-Internal", rules: rules) == .openAIChat)
        #expect(ModelAPIProtocol.resolve(model: "claude-haiku", rules: rules) == .anthropicMessages)
        #expect(ModelAPIProtocol.resolve(model: "gpt-4o", rules: rules) == .openAIChat)
    }

    // MARK: Requests

    @Test("Native URLs are built on the endpoint's site prefix")
    func buildsNativeURLs() throws {
        let builder = makeBuilder(endpoint: "https://gw.corp.example.com/v1/chat/completions", model: "gemini-2.5-pro")
        #expect(try builder.url(for: .anthropicMessages).absoluteString == "https://gw.corp.example.com/v1/messages")
        #expect(try builder.url(for: .openAIResponses).absoluteString == "https://gw.corp.example.com/v1/responses")
        #expect(
            try builder.url(for: .geminiGenerateContent).absoluteString
                == "https://gw.corp.example.com/v1beta/models/gemini-2.5-pro:streamGenerateContent?alt=sse"
        )

        let prefixed = makeBuilder(endpoint: "https://gw.corp.example.com/api/v1/chat/completions")
        #expect(try prefixed.url(for: .anthropicMessages)
            .absoluteString == "https://gw.corp.example.com/api/v1/messages")
    }

    @Test("Anthropic request uses native headers, top-level system, and image blocks")
    func anthropicRequest() throws {
        let builder = makeBuilder(model: "claude-sonnet-4-5")
        let headers = Dictionary(uniqueKeysWithValues: builder.headers(for: .anthropicMessages))
        #expect(headers["x-api-key"] == "sk-test")
        #expect(headers["anthropic-version"] == ModelAPIRequestBuilder.anthropicVersion)

        let body = try builder.body(for: .anthropicMessages, messages: sampleMessages)
        #expect(body["system"] as? String == "Be brief.")
        #expect(body["max_tokens"] as? Int == ModelAPIRequestBuilder.anthropicMaxTokens)

        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "user"])
        let blocks = try #require(messages.last?["content"] as? [[String: Any]])
        let source = try #require(blocks.first?["source"] as? [String: Any])
        #expect(source["media_type"] as? String == "image/png")
        #expect(source["data"] as? String == "AAAA")
        #expect(blocks.last?["text"] as? String == "And this?")
    }

    @Test("Gemini request maps roles, inline images, and system instruction")
    func geminiRequest() throws {
        let body = try makeBuilder(model: "gemini-2.5-pro").body(for: .geminiGenerateContent, messages: sampleMessages)

        let contents = try #require(body["contents"] as? [[String: Any]])
        #expect(contents.map { $0["role"] as? String } == ["user", "model", "user"])
        let parts = try #require(contents.last?["parts"] as? [[String: Any]])
        #expect(parts.first?["text"] as? String == "And this?")
        let inline = try #require(parts.last?["inline_data"] as? [String: Any])
        #expect(inline["mime_type"] as? String == "image/png")

        let system = try #require(body["systemInstruction"] as? [String: Any])
        let systemParts = try #require(system["parts"] as? [[String: Any]])
        #expect(systemParts.first?["text"] as? String == "Be brief.")
    }

    @Test("Responses request uses typed input parts and instructions")
    func responsesRequest() throws {
        let body = try makeBuilder(model: "gpt-5").body(for: .openAIResponses, messages: sampleMessages)
        #expect(body["instructions"] as? String == "Be brief.")
        #expect(body["temperature"] == nil)

        let input = try #require(body["input"] as? [[String: Any]])
        let assistantContent = try #require(input[1]["content"] as? [[String: Any]])
        #expect(assistantContent.first?["type"] as? String == "output_text")
        let userContent = try #require(input[2]["content"] as? [[String: Any]])
        #expect(userContent.map { $0["type"] as? String } == ["input_text", "input_image"])
        #expect(userContent.last?["image_url"] as? String == "data:image/png;base64,AAAA")
    }

    // MARK: Parsing

    @Test("Stream events yield text for each native format")
    func parsesStreamEvents() throws {
        let anthropic = """
        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}
        """
        #expect(try ModelAPIStreamParser.textDelta(in: anthropic, for: .anthropicMessages) == "Hi")

        let gemini = #"data: {"candidates":[{"content":{"parts":[{"text":"plan","thought":true},{"text":"Hi"}]}}]}"#
        #expect(try ModelAPIStreamParser.textDelta(in: gemini, for: .geminiGenerateContent) == "Hi")

        let responses = """
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"Hi"}
        """
        #expect(try ModelAPIStreamParser.textDelta(in: responses, for: .openAIResponses) == "Hi")

        let created = #"data: {"type":"response.created","response":{}}"#
        #expect(try ModelAPIStreamParser.textDelta(in: created, for: .openAIResponses) == nil)
    }

    @Test("Error bodies yield the server's message")
    func extractsErrorMessages() {
        let shapes = [
            #"{"error":{"message":"model not found","type":"invalid_request_error"}}"#,
            #"[{"error":{"code":404,"message":"model not found"}}]"#,
            #"{"error":"model not found"}"#,
            #"{"message":"model not found"}"#,
        ]
        for shape in shapes {
            #expect(ModelAPIStreamParser.errorMessage(from: Data(shape.utf8)) == "model not found")
        }
    }

    // MARK: End to end

    @Test("Anthropic models stream through the gateway's /v1/messages")
    func streamsAnthropicThroughGateway() async throws {
        let server = try LocalHTTPServer(responseBody: """
        event: message_start
        data: {"type":"message_start","message":{}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}

        event: message_stop
        data: {"type":"message_stop"}


        """)
        let request = try await stream(
            .anthropicMessages,
            model: "claude-sonnet-4-5",
            server: server,
            expect: "Hello world"
        )
        #expect(request.path == "/v1/messages")
        #expect(request.header("x-api-key") == "sk-test")
        #expect(request.header("anthropic-version") == ModelAPIRequestBuilder.anthropicVersion)
    }

    @Test("Gemini models stream through the gateway's streamGenerateContent")
    func streamsGeminiThroughGateway() async throws {
        let server = try LocalHTTPServer(responseBody: """
        data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Hello"}]}}]}

        data: {"candidates":[{"content":{"role":"model","parts":[{"text":" world"}]}}]}
        """)
        let request = try await stream(
            .geminiGenerateContent,
            model: "gemini-2.5-pro",
            server: server,
            expect: "Hello world"
        )
        #expect(request.path == "/v1beta/models/gemini-2.5-pro:streamGenerateContent?alt=sse")
        #expect(request.header("x-goog-api-key") == "sk-test")
    }

    @Test("Responses models stream through the gateway's /v1/responses")
    func streamsResponsesThroughGateway() async throws {
        let server = try LocalHTTPServer(responseBody: """
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"Hello"}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":" world"}

        event: response.completed
        data: {"type":"response.completed","response":{}}


        """)
        let request = try await stream(.openAIResponses, model: "gpt-5", server: server, expect: "Hello world")
        #expect(request.path == "/v1/responses")
        #expect(request.header("Authorization") == "Bearer sk-test")
    }

    @Test("Gateway errors surface the server's message")
    func surfacesGatewayErrors() async throws {
        let server = try LocalHTTPServer(
            statusCode: 404,
            responseBody: #"{"error":{"message":"model claude-x not found"}}"#
        )
        let baseURL = try await server.start()
        defer { server.stop() }

        let builder = makeBuilder(endpoint: "\(baseURL.absoluteString)/v1/chat/completions", model: "claude-x")
        await #expect {
            for try await _ in CustomOpenAIService().streamModelAPI(
                .anthropicMessages,
                builder: builder,
                messages: sampleMessages
            ) {}
        } throws: { error in
            (error as? QueryError)?.errorDataMessage == "model claude-x not found"
        }
    }

    // MARK: Private

    /// System prompt, one earlier exchange, and a question with an image.
    private let sampleMessages: [ChatMessage] = [
        .init(role: .system, content: "Be brief."),
        .init(role: .user, content: "What is this?"),
        .init(role: .assistant, content: "A cat."),
        .init(role: .user, content: "And this?", imageURLs: ["data:image/png;base64,AAAA"]),
    ]

    private func makeBuilder(
        endpoint: String = "https://gw.corp.example.com/v1/chat/completions",
        model: String = "claude-sonnet-4-5"
    )
        -> ModelAPIRequestBuilder {
        ModelAPIRequestBuilder(chatEndpoint: endpoint, apiKey: "sk-test", model: model, temperature: 0.3)
    }

    /// Streams `apiProtocol` from `server`, checks the joined text, and returns the request it received.
    private func stream(
        _ apiProtocol: ModelAPIProtocol,
        model: String,
        server: LocalHTTPServer,
        expect expectedText: String
    ) async throws
        -> LocalHTTPServer.Request {
        let baseURL = try await server.start()
        defer { server.stop() }

        let builder = makeBuilder(endpoint: "\(baseURL.absoluteString)/v1/chat/completions", model: model)
        var text = ""
        for try await delta in CustomOpenAIService().streamModelAPI(
            apiProtocol,
            builder: builder,
            messages: sampleMessages
        ) {
            text += delta
        }
        #expect(text == expectedText)
        return try #require(server.requests.first)
    }
}
