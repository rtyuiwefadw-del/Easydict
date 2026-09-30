//
//  RemoteModelsFetchTests.swift
//  EasydictTests
//
//  Created by wangjiapeng on 2026/9/30.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation
import Testing

@testable import Easydict

// MARK: - RemoteModelsFetchTests

/// Tests for "fetch models from cloud" on OpenAI-compatible services. A local
/// server stands in for a self-hosted gateway, such as a company endpoint,
/// to check that the request goes to the configured host with the expected
/// method, path, and headers, and that the returned model list is parsed.
@Suite("Remote Models Fetch", .tags(.unit))
struct RemoteModelsFetchTests {
    // MARK: Internal

    @Test("DeepSeek official endpoint keeps the documented models URL")
    func deepSeekOfficialEndpoint() throws {
        let url = try DeepSeekService().remoteModelsURL(
            chatEndpoint: "https://api.deepseek.com/v1/chat/completions"
        )
        #expect(url.absoluteString == "https://api.deepseek.com/models")
    }

    @Test("DeepSeek custom endpoint lists models from the same host")
    func deepSeekCustomEndpointUsesSameHost() throws {
        let url = try DeepSeekService().remoteModelsURL(
            chatEndpoint: "https://llm.corp.example.com/v1/chat/completions"
        )
        #expect(url.absoluteString == "https://llm.corp.example.com/v1/models")
    }

    @Test("DeepSeek fetch sends an OpenAI-compatible request to a custom endpoint")
    func deepSeekFetchHitsCustomEndpoint() async throws {
        let server = try LocalHTTPServer(responseBody: Self.modelListJSON)
        let baseURL = try await server.start()
        defer { server.stop() }

        let modelIDs = try await DeepSeekService().fetchRemoteModelIDs(
            chatEndpoint: "\(baseURL.absoluteString)/v1/chat/completions",
            apiKey: "sk-company-test-zYZl"
        )

        let request = try #require(server.requests.first)
        #expect(request.method == "GET")
        #expect(request.path == "/v1/models")
        #expect(request.header("Authorization") == "Bearer sk-company-test-zYZl")
        #expect(request.header("Accept") == "application/json")
        #expect(modelIDs == ["deepseek-v4-flash", "deepseek-v4-pro", "qwen3-coder"])
    }

    @Test("Custom OpenAI fetch derives the models path from the chat endpoint")
    func customOpenAIFetchUsesChatEndpointHost() async throws {
        let server = try LocalHTTPServer(responseBody: Self.modelListJSON)
        let baseURL = try await server.start()
        defer { server.stop() }

        let modelIDs = try await CustomOpenAIService().fetchRemoteModelIDs(
            chatEndpoint: "\(baseURL.absoluteString)/api/v1/chat/completions",
            apiKey: "sk-company-test"
        )

        let request = try #require(server.requests.first)
        #expect(request.path == "/api/v1/models")
        #expect(modelIDs.count == 3)
    }

    @Test("Surrounding whitespace in a pasted API key is not sent")
    func apiKeyWhitespaceIsTrimmed() async throws {
        let server = try LocalHTTPServer(responseBody: Self.modelListJSON)
        let baseURL = try await server.start()
        defer { server.stop() }

        _ = try await CustomOpenAIService().fetchRemoteModelIDs(
            chatEndpoint: "\(baseURL.absoluteString)/v1/chat/completions",
            apiKey: "  sk-company-test\n"
        )

        let request = try #require(server.requests.first)
        #expect(request.header("Authorization") == "Bearer sk-company-test")
        #expect(request.header("api-key") == "sk-company-test")
    }

    // MARK: Private

    private static let modelListJSON = """
    {"object":"list","data":[
      {"id":"deepseek-v4-flash","object":"model","owned_by":"company"},
      {"id":"deepseek-v4-pro","object":"model","owned_by":"company"},
      {"id":"qwen3-coder","object":"model","owned_by":"company"}
    ]}
    """
}
