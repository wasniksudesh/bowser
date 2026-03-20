// NavigationState.swift - Dedicated Navigation State Management
// Extracted from BrowserState for per-tab navigation tracking
// Swift 6.2 with @Observable macro for reactive UI

import Foundation
import SwiftUI

// =============================================================================
// MARK: - Security Level
// =============================================================================

/// Represents the security level of a URL for visual indicators
enum SecurityLevel: Sendable {
    case secure  // HTTPS
    case insecure  // HTTP
    case local  // file://
    case neutral  // about:, other schemes

    /// SF Symbol name for security indicator
    var iconName: String {
        switch self {
        case .secure: return "lock.fill"
        case .insecure: return "exclamationmark.triangle.fill"
        case .local: return "folder.fill"
        case .neutral: return "globe"
        }
    }

    /// Color for security indicator
    var color: Color {
        switch self {
        case .secure: return .green
        case .insecure: return .orange
        case .local: return .blue
        case .neutral: return .secondary
        }
    }

    /// Initialize from URL scheme
    init(from url: URL?) {
        guard let url, let scheme = url.scheme?.lowercased() else {
            self = .neutral
            return
        }

        switch scheme {
        case "https":
            self = .secure
        case "http":
            self = .insecure
        case "file":
            self = .local
        default:
            self = .neutral
        }
    }
}

// =============================================================================
// MARK: - Navigation State (Observable)
// =============================================================================

/// Dedicated manager for navigation-related state
/// Extracted from BrowserState God Object for single-responsibility
/// Represents the navigation state of the currently active tab/pane
@Observable
@MainActor
final class NavigationState {

    // MARK: - Properties

    /// Reference to settings for search engine configuration
    private let settingsManager: SettingsManager
    // MARK: - Initialization

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    // MARK: - Core Properties

    /// Current text in the address bar (editable by user)
    var addressBarText: String = ""

    /// Whether the current page is loading
    private(set) var isLoading: Bool = false

    /// Whether back navigation is available
    private(set) var canGoBack: Bool = false

    /// Whether forward navigation is available
    private(set) var canGoForward: Bool = false

    /// Page load progress (0.0 to 1.0), nil when not loading
    private(set) var loadProgress: Double?

    // MARK: - Computed Properties

    /// Parse addressBarText into a URL, handling search queries
    var parsedURL: URL? {
        let input = addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        // Check if it looks like a URL
        if looksLikeURL(input) {
            if input.hasPrefix("http://") || input.hasPrefix("https://") {
                return URL(string: input)
            } else if input.hasPrefix("file://") {
                return URL(string: input)
            } else {
                // Add https:// prefix
                return URL(string: "https://\(input)")
            }
        }

        // Treat as search query
        return settingsManager.searchURL(for: input)
    }

    /// Domain for display in address bar (strips www.)

    /// Domain for display in address bar (strips www.)
    var displayDomain: String {
        guard let url = parsedURL,
            let host = url.host
        else {
            return addressBarText.isEmpty ? "New Tab" : addressBarText
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Security level based on current URL scheme
    var securityLevel: SecurityLevel {
        SecurityLevel(from: parsedURL)
    }

    // MARK: - Methods

    /// Update navigation state from CEF callbacks
    /// - Parameters:
    ///   - isLoading: New loading state
    ///   - canGoBack: New back navigation state
    ///   - canGoForward: New forward navigation state
    ///   - loadProgress: Optional load progress (0.0-1.0)
    func update(
        isLoading: Bool? = nil,
        canGoBack: Bool? = nil,
        canGoForward: Bool? = nil,
        loadProgress: Double? = nil
    ) {
        if let isLoading { self.isLoading = isLoading }
        if let canGoBack { self.canGoBack = canGoBack }
        if let canGoForward { self.canGoForward = canGoForward }
        if let loadProgress { self.loadProgress = loadProgress }

        // Clear progress when loading completes
        if isLoading == false {
            self.loadProgress = nil
        }
    }

    /// Sync navigation state when switching tabs
    /// - Parameter tab: The tab to sync state from
    func syncFromTab(_ tab: Tab) {
        addressBarText = tab.activePaneURL.absoluteString
        canGoBack = tab.canGoBack
        canGoForward = tab.canGoForward
        isLoading = tab.activePaneIsLoading
        loadProgress = nil
    }

    /// Reset navigation state to defaults
    func reset() {
        addressBarText = ""
        isLoading = false
        canGoBack = false
        canGoForward = false
        loadProgress = nil
    }

    /// Parse and commit the current address bar text for navigation
    /// - Returns: Valid URL to navigate to, or nil if invalid
    func commitNavigation() -> URL? {
        return parsedURL
    }

    // MARK: - Private Helpers

    /// Heuristic to detect if input is a URL vs search query
    private func looksLikeURL(_ input: String) -> Bool {
        // Contains no spaces and has a dot (domain-like)
        if !input.contains(" ") && input.contains(".") {
            return true
        }

        // Starts with http/https/file
        if input.hasPrefix("http://") || input.hasPrefix("https://") || input.hasPrefix("file://") {
            return true
        }

        // Localhost
        if input.hasPrefix("localhost") {
            return true
        }

        // about: pages
        if input.hasPrefix("about:") {
            return true
        }

        return false
    }
}
