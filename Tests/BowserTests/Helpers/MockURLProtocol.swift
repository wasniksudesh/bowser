// MockURLProtocol.swift
// URLProtocol subclass that intercepts HTTP requests during tests.
// Register before a test, unregister after.
//
// Usage:
//   MockURLProtocol.register(
//       path: "/api/agent/goals/plan",
//       statusCode: 200,
//       json: ["session_id": "...", ...]
//   )
//   URLProtocol.registerClass(MockURLProtocol.self)
//   defer { URLProtocol.unregisterClass(MockURLProtocol.self) }

import Foundation

/// Thread-safe store for registered mock responses.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    // MARK: - Response store

    private struct MockResponse {
        let statusCode: Int
        let data: Data
    }

    private static let lock = NSLock()
    // nonisolated(unsafe): concurrency managed manually by `lock` above.
    nonisolated(unsafe) private static var responses: [String: MockResponse] = [:]

    /// Register a JSON response for a given URL path.
    static func register(path: String, statusCode: Int = 200, json: Any) {
        let data = try! JSONSerialization.data(withJSONObject: json)
        lock.withLock {
            responses[path] = MockResponse(statusCode: statusCode, data: data)
        }
    }

    /// Register a raw-data response (e.g. SSE stream bytes).
    static func register(path: String, statusCode: Int = 200, data: Data) {
        lock.withLock {
            responses[path] = MockResponse(statusCode: statusCode, data: data)
        }
    }

    /// Clear all registered responses.
    static func reset() {
        lock.withLock { responses.removeAll() }
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool {
        guard let path = request.url?.path else { return false }
        return lock.withLock { responses[path] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let path = request.url?.path else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let mock = MockURLProtocol.lock.withLock {
            MockURLProtocol.responses[path]
        }

        guard let mock else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: mock.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: mock.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
