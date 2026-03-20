// VSockClient.swift
// HTTP client that communicates over vsock instead of TCP/IP

import Foundation
import Network
import Virtualization

/// HTTP client for vsock communication with the VM backend
@available(macOS 14.0, *)
final class VSockClient: @unchecked Sendable {

    // MARK: - Properties

    private let vsockPort: UInt32 = 8765
    private let cid: UInt32  // Context ID of the VM
    private let timeout: TimeInterval = 30
    private let lock = NSLock()

    // MARK: - Initialization

    init(cid: UInt32) {
        self.cid = cid
    }

    // MARK: - HTTP Requests

    func get(_ path: String) async throws -> Data {
        try await request(method: "GET", path: path, body: nil)
    }

    func post(_ path: String, body: Data? = nil) async throws -> Data {
        try await request(method: "POST", path: path, body: body)
    }

    func postJSON<T: Encodable>(_ path: String, body: T) async throws -> Data {
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(body)
        return try await post(path, body: jsonData)
    }

    // MARK: - Core Request Handler

    private func request(method: String, path: String, body: Data?) async throws -> Data {
        let endpoint = NWEndpoint.hostPort(
            host: .init("\(cid)"),
            port: NWEndpoint.Port(rawValue: UInt16(vsockPort))!
        )

        // Use default parameters
        let parameters = NWParameters(tls: nil)

        // Attempt to set vsock transport
        // In some environments, NWProtocolVSOCK may need to be accessed via the framework
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()  // FIXME: Restore NWProtocolVSOCK.Options() once SDK issue is found

        let connection = NWConnection(to: endpoint, using: parameters)

        return try await withCheckedThrowingContinuation { continuation in
            let state = RequestState()

            let finish: @Sendable (Result<Data, Error>) -> Void = { result in
                state.lock.lock()
                if state.isFinished {
                    state.lock.unlock()
                    return
                }
                state.isFinished = true
                state.lock.unlock()

                connection.cancel()

                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            connection.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    self.sendHTTPRequest(
                        connection: connection,
                        method: method,
                        path: path,
                        body: body,
                        completion: finish
                    )
                case .failed(let error):
                    finish(.failure(error))
                case .waiting(let error):
                    print("[VSockClient] Waiting: \(error)")
                case .cancelled:
                    finish(.failure(VSockError.timeout))
                default:
                    break
                }
            }

            connection.start(queue: .global())

            // Timeout handler
            DispatchQueue.global().asyncAfter(deadline: .now() + self.timeout) {
                finish(.failure(VSockError.timeout))
            }
        }
    }

    // MARK: - HTTP Protocol Implementation

    private func sendHTTPRequest(
        connection: NWConnection,
        method: String,
        path: String,
        body: Data?,
        completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        var request = "\(method) \(path) HTTP/1.1\r\n"
        request += "Host: localhost\r\n"
        request += "Connection: close\r\n"

        if let body = body {
            request += "Content-Type: application/json\r\n"
            request += "Content-Length: \(body.count)\r\n"
        }
        request += "\r\n"

        guard let headersData = request.data(using: .utf8) else {
            completion(.failure(VSockError.invalidRequest))
            return
        }

        connection.send(
            content: headersData,
            completion: .contentProcessed { error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let body = body {
                    connection.send(
                        content: body,
                        completion: .contentProcessed { error in
                            if let error = error {
                                completion(.failure(error))
                                return
                            }
                            self.readHTTPResponse(connection: connection, completion: completion)
                        })
                } else {
                    self.readHTTPResponse(connection: connection, completion: completion)
                }
            })
    }

    private func readHTTPResponse(
        connection: NWConnection,
        completion: @escaping @Sendable (Result<Data, Error>) -> Void
    ) {
        let responseData = AtomicData()

        @Sendable func receive() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
                data, _, isComplete, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let data = data {
                    responseData.append(data)
                }

                if isComplete {
                    do {
                        let body = try self.parseHTTPResponse(responseData.data)
                        completion(.success(body))
                    } catch {
                        completion(.failure(error))
                    }
                } else {
                    receive()
                }
            }
        }
        receive()
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
        let request = ConfigRequest(provider: provider, api_key: apiKey, model: model)
        _ = try await postJSON("/api/ai/configure", body: request)
    }

    func executeTask(task: String, context: [String: String]?) async throws -> TaskResponse {
        struct TaskRequest: Codable {
            let task: String
            let context: [String: String]?
        }
        let request = TaskRequest(task: task, context: context)
        let data = try await postJSON("/api/ai/execute", body: request)
        return try JSONDecoder().decode(TaskResponse.self, from: data)
    }
}

// MARK: - Helper Types

private final class RequestState: @unchecked Sendable {
    var isFinished = false
    let lock = NSLock()
}

private final class AtomicData: @unchecked Sendable {
    private let lock = NSLock()
    private var _data = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return _data
    }

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        _data.append(data)
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
