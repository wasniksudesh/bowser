// CEFHandler.swift - CEF Event Handlers
// Delegates for CEF browser callbacks

import Foundation

// =============================================================================
// MARK: - CEF Handler Protocol
// =============================================================================

/// Protocol for receiving CEF browser events
/// Implement this to respond to page lifecycle and navigation events
@MainActor
protocol CEFHandlerDelegate: AnyObject, Sendable {
    
    /// Called when page starts loading
    /// - Parameters:
    ///   - browserID: Identifier for the browser instance
    ///   - url: URL being loaded
    func cefHandler(browserID: String, didStartLoading url: URL)
    
    /// Called when page finishes loading
    /// - Parameters:
    ///   - browserID: Identifier for the browser instance
    ///   - url: URL that loaded
    ///   - httpStatusCode: HTTP status code (200, 404, etc.)
    func cefHandler(browserID: String, didFinishLoading url: URL, httpStatusCode: Int)
    
    /// Called when page load fails
    /// - Parameters:
    ///   - browserID: Identifier for the browser instance
    ///   - url: URL that failed to load
    ///   - error: Error description
    func cefHandler(browserID: String, didFailLoading url: URL, error: String)
    
    /// Called when page title changes
    /// - Parameters:
    ///   - browserID: Identifier for the browser instance
    ///   - title: New page title
    func cefHandler(browserID: String, titleDidChange title: String)
    
    /// Called when favicon URL changes
    /// - Parameters:
    ///   - browserID: Identifier for the browser instance
    ///   - faviconURL: URL of the favicon
    func cefHandler(browserID: String, faviconDidChange faviconURL: URL)
    
    /// Called when navigation state changes
    /// - Parameters:
    ///   - browserID: Identifier for the browser instance
    ///   - canGoBack: Whether back navigation is available
    ///   - canGoForward: Whether forward navigation is available
    func cefHandler(browserID: String, navigationStateChanged canGoBack: Bool, canGoForward: Bool)
    
    /// Called when a console message is logged
    /// - Parameters:
    ///   - browserID: Identifier for the browser instance
    ///   - message: Console message text
    ///   - source: Source file
    ///   - line: Line number
    func cefHandler(browserID: String, consoleMessage message: String, source: String, line: Int)
}

// =============================================================================
// MARK: - CEF Handler
// =============================================================================

/// Handles CEF browser callbacks and dispatches to delegates
/// Uses @MainActor for safe UI updates
@MainActor
final class CEFHandler: Sendable {
    
    /// Weak reference to delegate
    weak var delegate: (any CEFHandlerDelegate)?
    
    /// Browser identifier for this handler
    let browserID: String
    
    // MARK: - Initialization
    
    init(browserID: String) {
        self.browserID = browserID
    }
    
    // MARK: - Callback Methods (called from C++)
    
    /// Handle load state change callback from CEF
    /// IPC FLOW: CEF C++ -> Swift callback -> @MainActor delegate
    func handleLoadStateChange(isLoading: Bool, urlString: String) {
        guard let url = URL(string: urlString) else { return }
        
        if isLoading {
            delegate?.cefHandler(browserID: browserID, didStartLoading: url)
        } else {
            delegate?.cefHandler(browserID: browserID, didFinishLoading: url, httpStatusCode: 200)
        }
    }
    
    /// Handle title change callback from CEF
    func handleTitleChange(title: String) {
        delegate?.cefHandler(browserID: browserID, titleDidChange: title)
    }
    
    /// Handle console message callback from CEF
    func handleConsoleMessage(message: String, source: String, line: Int) {
        delegate?.cefHandler(browserID: browserID, consoleMessage: message, source: source, line: line)
        
        // Also print to console for debugging
        print("[CEF Console] \(source):\(line) - \(message)")
    }
    
    // MARK: - Callback Registration
    
    /// Register C callbacks with CEF
    /// This wires up the CEF callback system to Swift methods
    func registerCallbacks(browserHandle: UnsafeMutableRawPointer) {
        print("[CEFHandler] Registering callbacks for browser: \(browserID)")
        
        // TODO: Uncomment when CEF is linked
        /*
        // Create callback closures that can be passed to C
        let loadStateCallback: @convention(c) (OpaquePointer?, Int32, UnsafePointer<CChar>?) -> Void = { browser, isLoading, url in
            // Dispatch to main actor
            Task { @MainActor in
                // Look up handler and call handleLoadStateChange
            }
        }
        
        let titleChangeCallback: @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Void = { browser, title in
            // Dispatch to main actor
            Task { @MainActor in
                // Look up handler and call handleTitleChange
            }
        }
        
        let consoleMessageCallback: @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, Int32) -> Void = { browser, message, source, line in
            // Dispatch to main actor
            Task { @MainActor in
                // Look up handler and call handleConsoleMessage
            }
        }
        
        cef_register_callbacks(browserHandle, loadStateCallback, titleChangeCallback, consoleMessageCallback)
        */
    }
}

// =============================================================================
// MARK: - Default Delegate Implementation
// =============================================================================

/// Default implementation of CEFHandlerDelegate for optional methods
extension CEFHandlerDelegate {
    func cefHandler(browserID: String, didStartLoading url: URL) {}
    func cefHandler(browserID: String, didFinishLoading url: URL, httpStatusCode: Int) {}
    func cefHandler(browserID: String, didFailLoading url: URL, error: String) {}
    func cefHandler(browserID: String, titleDidChange title: String) {}
    func cefHandler(browserID: String, faviconDidChange faviconURL: URL) {}
    func cefHandler(browserID: String, navigationStateChanged canGoBack: Bool, canGoForward: Bool) {}
    func cefHandler(browserID: String, consoleMessage message: String, source: String, line: Int) {}
}
