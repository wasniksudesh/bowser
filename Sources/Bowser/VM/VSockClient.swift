// VSockClient.swift
// HTTP client that communicates over VZVirtioSocketConnection instead of TCP/IP

import Foundation
@preconcurrency import Virtualization

/// HTTP client for vsock communication with the VM backend.
/// Uses VZVirtioSocketConnection (via VMManager) for host-to-guest IPC.
@available(macOS 14.0, *)
final class VSockClient: @unchecked Sendable {

    // MARK: - Properties

    private let vsockPort: UInt32 = 8765
    private let timeout: TimeInterval = 30

    // MARK: - Initialization

    init() {}

    // MARK: - HTTP Requests

    func get(_ path: String) async throws -> Data {
        try await request(method: "GET", path: path, body: nil)
    }

    func post(_ path: String, body: Data? = nil) async throws -> Data {
        try await request(method: "POST", path: path, body: body)
    }

    func postJSON<T: Encodable>(_ path: String, body: T) async throws -> Data {
        let jsonData = try JSONEncoder().encode(body)
        return try await post(path, body: jsonData)
    }

    // MARK: - Core Request Handler

    private func request(method: String, path: String, body: Data?) async throws -> Data {
        let connection = try await VMManager.shared.connectToPort(vsockPort)

        return try await withThrowingTaskGroup(of: Data.self) { group in
            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(self.timeout * 1_000_000_000))
                throw VSockError.timeout
            }

            // Request task
            group.addTask {
                defer { connection.close() }
                try self.sendHTTPRequest(
                    connection: connection,
                    method: method,
                    path: path,
                    body: body
                )
                return try self.readHTTPResponse(connection: connection)
            }

            // Return whichever finishes first; cancel the other
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // MARK: - HTTP Protocol Implementation

    private func sendHTTPRequest(
        connection: VZVirtioSocketConnection,
        method: String,
        path: String,
        body: Data?
    ) throws {
        var headers = "\(method) \(path) HTTP/1.1\r\n"
        headers += "Host: localhost\r\n"
        headers += "Connection: close\r\n"
        if let body = body {
            headers += "Content-Type: application/json\r\n"
            headers += "Content-Length: \(body.count)\r\n"
        }
        headers += "\r\n"

        guard let headerData = headers.data(using: .utf8) else {
            throw VSockError.invalidRequest
        }

        let writeHandle = FileHandle(fileDescriptor: connection.fileDescriptor, closeOnDealloc: false)
        writeHandle.write(headerData)
        if let body = body {
            writeHandle.write(body)
        }
    }

    private func readHTTPResponse(connection: VZVirtioSocketConnection) throws -> Data {
        let readHandle = FileHandle(fileDescriptor: connection.fileDescriptor, closeOnDealloc: false)
        var accumulated = Data()

        // Read in chunks until the connection is closed by the guest
        while true {
            let chunk = readHandle.availableData
            if chunk.isEmpty { break }
            accumulated.append(chunk)
        }

        return try parseHTTPResponse(accumulated)
    }

    private func parseHTTPResponse(_ data: Data) throws -> Data {
        guard let responseString = String(data: data, encoding: .utf8) else {
            throw VSockError.invalidResponse
        }

        let components = responseString.components(separatedBy: "\r\n\r\n")
        guard components.count >= 2 else {
            throw VSockError.invalidResponse
        }

        let headers = components[0]
        let bodyString = components.dropFirst().joined(separator: "\r\n\r\n")

        let headerLines = headers.components(separatedBy: "\r\n")
        guard let statusLine = headerLines.first else {
            throw VSockError.invalidResponse
        }

        let statusParts = statusLine.components(separatedBy: " ")
        guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else {
            throw VSockError.invalidResponse
        }

        if statusCode >= 400 {
            throw VSockError.httpError(statusCode, bodyString)
        }

        guard let bodyData = bodyString.data(using: .utf8) else {
            throw VSockError.invalidResponse
        }

        return bodyData
    }

    // MARK: - Convenience Methods

    func healthCheck() async throws -> Bool {
        do {
            let data = try await get("/health")
            let response = try JSONDecoder().decode(HealthResponse.self, from: data)
            return response.status == "healthy"
        } catch {
            return false
        }
    }

    func configure(provider: String, apiKey: String, model: String?) async throws {
        struct ConfigRequest: Codable {
            let provider: String
            let api_key: String
            let model: String?
        }
        let requestBody = ConfigRequest(provider: provider, api_key: apiKey, model: model)
        _ = try await postJSON("/api/ai/configure", body: requestBody)
    }

    func executeTask(task: String, context: [String: String]?) async throws -> TaskResponse {
        struct TaskRequest: Codable {
            let task: String
            let context: [String: String]?
        }
        let requestBody = TaskRequest(task: task, context: context)
        let data = try await postJSON("/api/ai/execute", body: requestBody)
        return try JSONDecoder().decode(TaskResponse.self, from: data)
    }

    /// Generic POST for any endpoint — used by AIService in production mode
    func performRequest(method: String, path: String, body: Data?) async throws -> Data {
        try await request(method: method, path: path, body: body)
    }
}

// MARK: - Models

struct HealthResponse: Codable {
    let status: String
    let version: String
    let timestamp: String
}

struct TaskResponse: Codable {
    let success: Bool
    let output: String?
    let error: String?
}

enum VSockError: LocalizedError {
    case timeout
    case invalidRequest
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .timeout: return "Request timed out"
        case .invalidRequest: return "Invalid HTTP request"
        case .invalidResponse: return "Invalid HTTP response"
        case .httpError(let code, let message): return "HTTP \(code): \(message)"
        }
    }
}
