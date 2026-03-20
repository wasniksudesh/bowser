// BrowserEngineProtocol.swift - Engine Abstraction Layer
// Decouples SwiftUI UI from CEF backend, enabling future engine swapping
// Swift 6.2 with @MainActor isolation

import AppKit
import Foundation

// =============================================================================
// MARK: - Browser Handle
// =============================================================================

/// Sendable identifier for browser instances across the abstraction layer
/// Combines tab-level UUID with engine-specific identifier
public struct BrowserHandle: Sendable, Hashable {
    /// Tab-level unique identifier (from TabModel)
    public let id: UUID

    /// Engine-specific browser identifier (e.g., CEF browser ID)
    /// Using Int64 for compatibility with C++ handles
    public let engineId: Int64

    public init(id: UUID, engineId: Int64) {
        self.id = id
        self.engineId = engineId
    }
}

// =============================================================================
// MARK: - Window Disposition
// =============================================================================

/// Disposition for new window/tab creation requests from the engine
/// Matches CEF's WindowOpenDisposition
public enum WindowDisposition: Sendable {
    /// Navigate in the current tab
    case currentTab
    /// Open in a new foreground tab
    case newForegroundTab
    /// Open in a new background tab
    case newBackgroundTab
    /// Open in a new popup window
    case newPopup
    /// Open in a new browser window
    case newWindow
}

// =============================================================================
// MARK: - Browser Engine Error
// =============================================================================

/// Errors that can occur during browser engine operations
public enum BrowserEngineError: Error, Sendable {
    /// Engine has not been initialized
    case notInitialized
    /// Browser with the specified ID was not found
    case browserNotFound(UUID)
    /// Navigation to the URL failed
    case navigationFailed(String)
    /// Snapshot capture failed
    case snapshotFailed
}

// =============================================================================
// MARK: - Browser Engine Delegate
// =============================================================================

/// Protocol for receiving browser engine state updates
/// All methods are called on MainActor for safe UI updates
@MainActor
public protocol BrowserEngineDelegate: AnyObject {

    /// Called when the loading state changes
    /// - Parameters:
    ///   - handle: The browser handle
    ///   - isLoading: True if the page is currently loading
    ///   - canGoBack: True if browser can navigate back in history
    ///   - canGoForward: True if browser can navigate forward in history
    ///   - url: The URL being loaded (nil during initial load)
    func engineDidChangeLoadingState(
        handle: BrowserHandle,
        isLoading: Bool,
        canGoBack: Bool,
        canGoForward: Bool,
        url: URL?
    )

    /// Called when the page title changes
    /// - Parameters:
    ///   - handle: The browser handle
    ///   - title: The new page title
    func engineDidChangeTitle(handle: BrowserHandle, title: String)

    /// Called when the URL changes (navigation)
    /// - Parameters:
    ///   - handle: The browser handle
    ///   - url: The new URL
    func engineDidChangeURL(handle: BrowserHandle, url: URL)

    /// Called when the favicon URL changes
    /// - Parameters:
    ///   - handle: The browser handle
    ///   - faviconURL: The URL of the favicon (nil if no favicon available)
    func engineDidChangeFaviconURL(handle: BrowserHandle, faviconURL: URL?)

    /// Called when a tab preview snapshot is ready
    /// - Parameters:
    ///   - handle: The browser handle
    ///   - preview: The captured preview image
    func engineDidCapturePreview(handle: BrowserHandle, preview: NSImage)

    /// Called when the engine requests opening a new tab/window
    /// - Parameters:
    ///   - handle: The source browser handle
    ///   - url: The URL to open
    ///   - disposition: How the URL should be opened
    func engineRequestsNewTab(handle: BrowserHandle, url: URL, disposition: WindowDisposition)

    /// Called when a website requests camera/microphone access
    /// - Parameters:
    ///   - handle: The browser handle
    ///   - origin: The requesting origin URL string
    ///   - permissions: Bitmask of requested permissions (1=audio, 2=video, 3=both)
    func engineDidRequestMediaPermission(handle: BrowserHandle, origin: String, permissions: Int)
}

// =============================================================================
// MARK: - Browser Engine Protocol
// =============================================================================

/// Main abstraction protocol for browser engines
/// Enables swapping CEF for other engines (e.g., WebKit) without UI changes
@MainActor
public protocol BrowserEngineProtocol: AnyObject, Sendable {

    // MARK: - State

    /// Whether the engine has been initialized
    var isInitialized: Bool { get }

    // MARK: - Lifecycle

    /// Initialize the browser engine
    /// Must be called before creating any browsers
    /// - Returns: True if initialization succeeded
    func initialize() async -> Bool

    /// Shutdown the browser engine and release all resources
    /// Must be called before application terminates
    func shutdown() async

    // MARK: - Browser Management

    /// Create a new browser instance
    /// - Parameters:
    ///   - id: Unique identifier for the browser (typically from TabModel.id)
    ///   - url: Initial URL to load
    ///   - delegate: Delegate to receive state updates (held weakly)
    /// - Returns: Browser handle on success, nil on failure
    func createBrowser(id: UUID, url: URL, delegate: BrowserEngineDelegate?) async -> BrowserHandle?

    /// Destroy a browser instance
    /// - Parameter handle: The browser handle to destroy
    func destroyBrowser(_ handle: BrowserHandle) async

    /// Get the native view for a browser (for embedding in UI)
    /// - Parameter handle: The browser handle
    /// - Returns: The native NSView for the browser, or nil if not found
    func getNativeView(for handle: BrowserHandle) -> NSView?

    // MARK: - Navigation

    /// Navigate to a URL
    /// - Parameters:
    ///   - handle: The browser handle
    ///   - url: URL to navigate to
    func navigate(_ handle: BrowserHandle, to url: URL) async

    /// Go back in history
    /// - Parameter handle: The browser handle
    func goBack(_ handle: BrowserHandle) async

    /// Go forward in history
    /// - Parameter handle: The browser handle
    func goForward(_ handle: BrowserHandle) async

    /// Reload the current page
    /// - Parameter handle: The browser handle
    func reload(_ handle: BrowserHandle) async

    /// Stop loading the current page
    /// - Parameter handle: The browser handle
    func stopLoading(_ handle: BrowserHandle) async

    // MARK: - State Queries

    /// Check if the browser can go back in history
    /// - Parameter handle: The browser handle
    /// - Returns: True if back navigation is available
    func canGoBack(_ handle: BrowserHandle) -> Bool

    /// Check if the browser can go forward in history
    /// - Parameter handle: The browser handle
    /// - Returns: True if forward navigation is available
    func canGoForward(_ handle: BrowserHandle) -> Bool

    /// Check if the browser is currently loading
    /// - Parameter handle: The browser handle
    /// - Returns: True if a page load is in progress
    func isLoading(_ handle: BrowserHandle) -> Bool

    /// Get the current URL
    /// - Parameter handle: The browser handle
    /// - Returns: The current URL, or nil if not available
    func currentURL(_ handle: BrowserHandle) -> URL?

    /// Get the current page title
    /// - Parameter handle: The browser handle
    /// - Returns: The current title, or nil if not available
    func currentTitle(_ handle: BrowserHandle) -> String?

    // MARK: - View Management

    /// Resize the browser view
    /// - Parameters:
    ///   - handle: The browser handle
    ///   - size: New size for the browser view
    func resize(_ handle: BrowserHandle, to size: CGSize) async

    // MARK: - Snapshots

    /// Capture a snapshot of the browser view for tab previews
    /// - Parameter handle: The browser handle
    /// - Returns: The captured image, or nil on failure
    func captureSnapshot(_ handle: BrowserHandle) async -> NSImage?

    // MARK: - Permissions

    /// Respond to a media permission request
    /// - Parameters:
    ///   - handle: The browser handle
    ///   - permissions: Bitmask of allowed permissions (0=deny, 1=audio, 2=video, 3=both)
    func respondToMediaPermission(_ handle: BrowserHandle, permissions: Int) async
}

// =============================================================================
// MARK: - Browser Engine Factory
// =============================================================================

/// Factory for creating browser engine instances
@MainActor
public enum BrowserEngineFactory {

    /// Create the default browser engine (CEF)
    /// - Returns: A configured CEF browser engine
    public static func createDefault() -> any BrowserEngineProtocol {
        return CEFBrowserEngine()
    }

    /// Create a mock browser engine for testing
    /// - Returns: A mock browser engine that tracks method calls
    public static func createMock() -> any BrowserEngineProtocol {
        return MockBrowserEngine()
    }
}
