//
//  LocalHTTPServer.swift
//  EasydictTests
//
//  Created by wangjiapeng on 2026/9/30.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation
import Network

// MARK: - LocalHTTPServer

/// Minimal loopback HTTP server for tests that must inspect the exact request
/// a service sends. It records each request head (request line and headers),
/// answers with a fixed status and JSON body, and never leaves 127.0.0.1.
final class LocalHTTPServer: @unchecked Sendable {
    // MARK: Lifecycle

    init(statusCode: Int = 200, responseBody: String) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        self.listener = try NWListener(using: parameters)
        self.statusCode = statusCode
        self.responseBody = Data(responseBody.utf8)
    }

    deinit {
        listener.cancel()
    }

    // MARK: Internal

    /// A received request, split into its request line and headers.
    struct Request {
        let method: String
        let path: String
        let headers: [String: String]

        /// Case-insensitive header lookup, matching HTTP semantics.
        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    /// Requests received so far, in arrival order.
    var requests: [Request] {
        lock.withLock { receivedRequests }
    }

    /// Starts listening and returns the base URL, such as `http://127.0.0.1:52011`.
    func start() async throws -> URL {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            listener.stateUpdateHandler = { [weak self] state in
                guard !didResume else { return }
                switch state {
                case .ready:
                    didResume = true
                    continuation.resume(returning: self?.listener.port?.rawValue ?? 0)
                case let .failed(error):
                    didResume = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }

        return URL(string: "http://127.0.0.1:\(port)")!
    }

    func stop() {
        listener.cancel()
    }

    // MARK: Private

    private let listener: NWListener
    private let statusCode: Int
    private let responseBody: Data
    private let queue = DispatchQueue(label: "EasydictTests.LocalHTTPServer")
    private let lock = NSLock()
    private var receivedRequests: [Request] = []

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveHead(on: connection, buffer: Data())
    }

    /// Reads until the blank line that ends the request head, then replies.
    private func receiveHead(on connection: NWConnection, buffer: Data) {
        connection
            .receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
                guard let self else { return }

                var buffer = buffer
                if let data {
                    buffer.append(data)
                }

                let terminator = Data("\r\n\r\n".utf8)
                guard let headEnd = buffer.range(of: terminator) else {
                    if error == nil, !isComplete {
                        receiveHead(on: connection, buffer: buffer)
                    } else {
                        connection.cancel()
                    }
                    return
                }

                let head = String(decoding: buffer[..<headEnd.lowerBound], as: UTF8.self)
                if let request = parse(head) {
                    lock.withLock { self.receivedRequests.append(request) }
                }
                respond(on: connection)
            }
    }

    private func parse(_ head: String) -> Request? {
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        return Request(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers)
    }

    private func respond(on connection: NWConnection) {
        var response = Data(
            """
            HTTP/1.1 \(statusCode) OK\r
            Content-Type: application/json\r
            Content-Length: \(responseBody.count)\r
            Connection: close\r
            \r

            """.utf8
        )
        response.append(responseBody)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
