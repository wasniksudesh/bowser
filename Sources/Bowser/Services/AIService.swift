// AIService.swift - Python Sidecar Client
// In development mode: URLSession over TCP to localhost:8765
// In production mode: HTTP-over-vsock through VSockClient / VMManager

import Foundation

// =============================================================================
// MARK: - AI Service
// =============================================================================

/// Client for communicating with the Python AI sidecar.
///
/// Mode switching:
/// - `.development` (DEBUG or non-.app bundle): URLSession to localhost:8765
/// - `.production` (.app bundle, non-DEBUG): VSockClient through VMManager
@MainActor
final class AIService: Sendable {

    /// Shared singleton instance
    static let shared = AIService()

    /// Base URL used in development mode only
    private let devBaseURL = URL(string: "http://localhost:8765")!

    /// URL session for dev-mode requests
    private let session: URLSession

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Transport

    /// True when running in production (VM) mode
    private var isProduction: Bool {
        BackendService.shared.mode == .production
    }

    /// Perform a raw HTTP request. Routes to vsock in production, URLSession in dev.
    private func performRequest(method: String, path: String, body: Data?) async throws -> Data {
        if isProduction {
            let client = VSockClient()
            return try await client.performRequest(method: method, path: path, body: body)
        }

        let url = devBaseURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        guard http.statusCode < 400 else {
            throw AIServiceError.httpError(statusCode: http.statusCode)
        }
        return data
    }

    // MARK: - API Methods

    /// Check if the sidecar is healthy
    func isHealthy() async -> Bool {
        do {
            _ = try await performRequest(method: "GET", path: "/health", body: nil)
            return true
        } catch {
            return false
        }
    }

    /// Analyze content using the AI backend
    func analyze(content: String) async throws -> String {
        let body = try JSONEncoder().encode(AnalyzeRequest(content: content))
        let data = try await performRequest(method: "POST", path: "/analyze", body: body)
        let result = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
        return result.result
    }

    /// Configure the AI agent with a new provider and API key
    func configureAI(provider: String, apiKey: String) async throws {
        let body = try JSONEncoder().encode(AIConfigureRequest(provider: provider, api_key: apiKey))
        let data = try await performRequest(method: "POST", path: "/api/ai/configure", body: body)
        let result = try JSONDecoder().decode(AIConfigureResponse.self, from: data)
        if !result.success {
            throw AIServiceError.configurationFailed(message: result.message)
        }
    }

    /// Resolve a natural language query to a direct URL using AI
    func resolveURL(query: String, model: String? = nil) async throws -> String {
        let body = try JSONEncoder().encode(ResolveURLRequest(query: query, model: model))
        let data = try await performRequest(method: "POST", path: "/api/ai/resolve-url", body: body)
        let result = try JSONDecoder().decode(ResolveURLResponse.self, from: data)
        return result.url
    }
}

// =============================================================================
// MARK: - Request/Response Models
// =============================================================================

struct AnalyzeRequest: Codable, Sendable {
    let content: String
}

struct AnalyzeResponse: Codable, Sendable {
    let result: String
    let timestamp: String?
}

struct AIConfigureRequest: Codable, Sendable {
    let provider: String
    let api_key: String
    let model: String?

    init(provider: String, api_key: String, model: String? = nil) {
        self.provider = provider
        self.api_key = api_key
        self.model = model
    }
}

struct AIConfigureResponse: Codable, Sendable {
    let success: Bool
    let message: String
}

struct ResolveURLRequest: Codable, Sendable {
    let query: String
    let model: String?
}

struct ResolveURLResponse: Codable, Sendable {
    let url: String
    let steps: [String]
}

// =============================================================================
// MARK: - Errors
// =============================================================================

enum AIServiceError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case configurationFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from AI sidecar"
        case .httpError(let statusCode):
            return "HTTP error \(statusCode) from AI sidecar"
        case .decodingError(let error):
            return "Failed to decode AI response: \(error.localizedDescription)"
        case .configurationFailed(let message):
            return "Configuration failed: \(message)"
        }
    }
}
