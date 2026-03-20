// AIService.swift - Python Sidecar Client
// URLSession-based client for FastAPI AI endpoints

import Foundation

// =============================================================================
// MARK: - AI Service
// =============================================================================

/// Client for communicating with the Python AI sidecar
/// Uses async/await and URLSession for HTTP requests
/// IPC FLOW: Swift AIService -> HTTP Request -> Python FastAPI -> JSON Response -> Swift
@MainActor
final class AIService: Sendable {

    /// Shared singleton instance
    static let shared = AIService()

    /// Base URL for the Python sidecar
    private let baseURL: URL

    /// URL session for requests
    private let session: URLSession

    // MARK: - Initialization

    private init() {
        self.baseURL = URL(string: "http://localhost:8765")!

        // Configure session with reasonable timeouts
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - API Methods

    /// Check if the sidecar is healthy
    /// - Returns: True if sidecar responds with 200 OK
    func isHealthy() async -> Bool {
        let url = baseURL.appendingPathComponent("health")

        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Analyze content using the AI backend
    /// - Parameter content: Content to analyze (URL, text, etc.)
    /// - Returns: Analysis result string
    /// - Throws: AIServiceError on failure
    func analyze(content: String) async throws -> String {
        let url = baseURL.appendingPathComponent("analyze")

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Encode body
        let body = AnalyzeRequest(content: content)
        request.httpBody = try JSONEncoder().encode(body)

        // Make request
        let (data, response) = try await session.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AIServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        // Decode response
        let result = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
        return result.result
    }

    /// Configure the AI agent with a new API key
    /// - Parameters:
    ///   - provider: AI provider (e.g., "openai", "anthropic")
    ///   - apiKey: API key for the provider
    /// - Throws: AIServiceError on failure
    func configureAI(provider: String, apiKey: String) async throws {
        let url = baseURL.appendingPathComponent("api/ai/configure")

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Encode body
        let body = AIConfigureRequest(provider: provider, api_key: apiKey)
        request.httpBody = try JSONEncoder().encode(body)

        // Make request
        let (data, response) = try await session.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AIServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        // Decode response to verify success
        let result = try JSONDecoder().decode(AIConfigureResponse.self, from: data)
        if !result.success {
            throw AIServiceError.configurationFailed(message: result.message)
        }
    }

    /// Resolve a natural language query to a direct URL using AI
    /// - Parameter query: Natural language query (e.g., "generate gpg keys on github")
    /// - Returns: Resolved URL string
    /// - Throws: AIServiceError on failure
    func resolveURL(query: String, model: String? = nil) async throws -> String {
        let url = baseURL.appendingPathComponent("api/ai/resolve-url")

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Encode body
        let body = ResolveURLRequest(query: query, model: model)
        request.httpBody = try JSONEncoder().encode(body)

        // Make request
        let (data, response) = try await session.data(for: request)

        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AIServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        // Decode response
        let result = try JSONDecoder().decode(ResolveURLResponse.self, from: data)
        return result.url
    }
}

// =============================================================================
// MARK: - Request/Response Models
// =============================================================================

/// Request body for /analyze endpoint
struct AnalyzeRequest: Codable, Sendable {
    let content: String
}

/// Response body from /analyze endpoint
struct AnalyzeResponse: Codable, Sendable {
    let result: String
    let timestamp: String?
}

/// Request body for /configure endpoint
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

/// Response body from /configure endpoint
struct AIConfigureResponse: Codable, Sendable {
    let success: Bool
    let message: String
}

/// Request body for /resolve-url endpoint
struct ResolveURLRequest: Codable, Sendable {
    let query: String
    let model: String?
}

/// Response body from /resolve-url endpoint
struct ResolveURLResponse: Codable, Sendable {
    let url: String
    let steps: [String]
}

// =============================================================================
// MARK: - Errors
// =============================================================================

/// Errors from AI service communication
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
