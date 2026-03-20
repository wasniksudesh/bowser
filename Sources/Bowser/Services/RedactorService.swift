// RedactorService.swift - Content Redaction Client
// Communicates with Python Sidecar redactor endpoint

import Foundation
import AppKit

// =============================================================================
// MARK: - Models
// =============================================================================

/// Request model for redaction
private struct RedactRequest: Codable {
    let type: String  // "text" or "image"
    let content: String
}

/// Response model for redaction
private struct RedactResponse: Codable {
    let type: String
    let content: String
}

// =============================================================================
// MARK: - Redactor Service
// =============================================================================

/// Client for communicating with the Python redactor service
/// Handles clipboard content redaction (PII in text, faces in images)
@MainActor
final class RedactorService {
    
    /// Shared singleton instance
    static let shared = RedactorService()
    
    /// Base URL for the Python sidecar
    private let baseURL: URL
    
    /// URL session for requests
    private let session: URLSession
    
    // MARK: - Initialization
    
    private init() {
        self.baseURL = URL(string: "http://localhost:8765")!
        
        // Configure session with timeout for redaction operations
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5  // 5 second timeout
        config.timeoutIntervalForResource = 10
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Public Methods
    
    /// Redact clipboard content in place
    /// Reads from NSPasteboard, sends to backend for redaction, updates clipboard
    /// - Returns: True if content was redacted, false if skipped or failed
    func redactClipboardContent() async -> Bool {
        let pasteboard = NSPasteboard.general
        
        // Try to redact image first
        // Check for common image formats on macOS clipboard
        var imageData: Data?
        if let pngData = pasteboard.data(forType: .png) {
            imageData = pngData
        } else if let tiffData = pasteboard.data(forType: .tiff) {
            imageData = tiffData
        }
        
        if let imageData = imageData {
            do {
                let redactedData = try await redactImage(imageData)
                pasteboard.clearContents()
                pasteboard.setData(redactedData, forType: .png)
                print("✓ Redacted image content")
                return true
            } catch {
                print("⚠ Image redaction failed: \(error.localizedDescription)")
                // Fall through to allow paste of original content
            }
        }
        
        // Try to redact text
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            do {
                let redactedText = try await redactText(text)
                if redactedText != text {
                    pasteboard.clearContents()
                    pasteboard.setString(redactedText, forType: .string)
                    print("✓ Redacted text content")
                    return true
                }
            } catch {
                print("⚠ Text redaction failed: \(error.localizedDescription)")
                // Fall through to allow paste of original content
            }
        }
        
        return false
    }
    
    /// Redact an image (blur faces)
    /// - Parameter data: Image data (PNG, JPEG, TIFF)
    /// - Returns: Redacted image data as PNG
    func redactImage(_ data: Data) async throws -> Data {
        // Convert image data to base64 data URL
        let base64String = data.base64EncodedString()
        let dataURL = "data:image/png;base64,\(base64String)"
        
        // Send to backend
        let request = RedactRequest(type: "image", content: dataURL)
        let response = try await sendRedactRequest(request)
        
        // Parse response data URL
        guard let base64Data = extractBase64FromDataURL(response.content) else {
            throw RedactorError.invalidResponse
        }
        
        guard let redactedData = Data(base64Encoded: base64Data) else {
            throw RedactorError.invalidBase64
        }
        
        return redactedData
    }
    
    /// Redact text (remove PII)
    /// - Parameter text: Plain text to redact
    /// - Returns: Redacted text with PII replaced
    func redactText(_ text: String) async throws -> String {
        let request = RedactRequest(type: "text", content: text)
        let response = try await sendRedactRequest(request)
        return response.content
    }
    
    // MARK: - Private Methods
    
    /// Send redaction request to backend
    private func sendRedactRequest(_ request: RedactRequest) async throws -> RedactResponse {
        let url = baseURL.appendingPathComponent("api/redactor/process")
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RedactorError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw RedactorError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let redactResponse = try JSONDecoder().decode(RedactResponse.self, from: data)
        return redactResponse
    }
    
    /// Extract base64 data from data URL
    /// - Parameter dataURL: Data URL string (e.g., "data:image/png;base64,...")
    /// - Returns: Base64 string without prefix
    private func extractBase64FromDataURL(_ dataURL: String) -> String? {
        guard let commaIndex = dataURL.firstIndex(of: ",") else {
            return nil
        }
        return String(dataURL[dataURL.index(after: commaIndex)...])
    }
}

// =============================================================================
// MARK: - Errors
// =============================================================================

enum RedactorError: LocalizedError {
    case invalidResponse
    case invalidBase64
    case httpError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from redactor service"
        case .invalidBase64:
            return "Failed to decode base64 image data"
        case .httpError(let code):
            return "Redactor service returned error: \(code)"
        }
    }
}
