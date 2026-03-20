// CEFBridge.swift - Swift-C++ Interop Wrapper for CEF
// Swift 6.2 direct C++ interop (no Objective-C bridging)

import CEFWrapper
import Foundation

// =============================================================================
// MARK: - CEF Bridge
// =============================================================================

/// Swift wrapper for CEF C++ API calls
/// Uses Swift 6.2 direct C++ interop features
/// All methods are thread-safe and use @MainActor for UI operations
@MainActor
final class CEFBridge: Sendable {

    /// Shared singleton instance
    static let shared = CEFBridge()

    /// Whether CEF has been initialized
    private(set) var isInitialized: Bool = false

    /// Active browser instances (keyed by view ID)
    private var browsers: [ObjectIdentifier: CefBrowserHandle] = [:]

    // MARK: - Initialization

    private init() {}

    /// Initialize CEF with default settings
    /// Must be called on the main thread before creating any browsers
    /// - Parameter sandboxEnabled: Whether to enable CEF sandboxing
    /// - Returns: True if initialization succeeded
    func initialize(sandboxEnabled: Bool = false) -> Bool {
        guard !isInitialized else {
            print("[CEFBridge] Already initialized")
            return true
        }

        print("[CEFBridge] Initializing CEF (sandbox: \(sandboxEnabled))...")

        // Call the C shim initializer
        let result = cef_simple_initialize()
        if result != 1 {  // CefInitialize returns true (1) on success
            print("[CEFBridge] CEF initialization failed!")
            return false
        }

        isInitialized = true
        print("[CEFBridge] CEF initialization complete")
        return true
    }

    /// Shutdown CEF and release all resources
    /// Must be called before application terminates
    func shutdown() {
        guard isInitialized else { return }

        print("[CEFBridge] Shutting down CEF...")

        // Destroy all active browsers
        for (_, handle) in browsers {
            cef_destroy_browser(handle)
        }
        browsers.removeAll()

        cef_simple_shutdown()

        isInitialized = false
        print("[CEFBridge] CEF shutdown complete")
    }

    // MARK: - Browser Management

    /// Create a new browser instance
    /// - Parameters:
    ///   - parentView: NSView to host the browser
    ///   - url: Initial URL to load
    ///   - size: Initial size
    ///   - disableSwipeNavigation: Whether to disable trackpad swipe gestures for back/forward
    /// - Returns: Opaque handle to the browser instance
    func createBrowser(
        parentView: AnyObject,
        url: URL,
        size: CGSize,
        disableSwipeNavigation: Bool = false
    ) -> CefBrowserHandle? {
        guard isInitialized else {
            print("[CEFBridge] CEF not initialized")
            return nil
        }

        let viewID = ObjectIdentifier(parentView)
        print(
            "[CEFBridge] Creating browser for view \(viewID) with URL: \(url), disableSwipeNavigation: \(disableSwipeNavigation)"
        )

        let handle = url.absoluteString.withCString { urlCString in
            cef_create_browser(
                Unmanaged.passUnretained(parentView).toOpaque(),
                urlCString,
                Int32(size.width),
                Int32(size.height),
                disableSwipeNavigation ? 1 : 0
            )
        }

        if let handle = handle {
            browsers[viewID] = handle
            return handle
        }

        return nil
    }

    /// Destroy a browser instance
    /// - Parameter handle: Browser handle from createBrowser
    func destroyBrowser(_ handle: CefBrowserHandle) {
        print("[CEFBridge] Destroying browser")

        // Remove from tracking
        browsers = browsers.filter { $0.value != handle }

        cef_destroy_browser(handle)
    }

    // MARK: - Navigation

    /// Navigate to a URL
    /// - Parameters:
    ///   - handle: Browser handle
    ///   - url: URL to navigate to
    func navigate(handle: CefBrowserHandle, to url: URL) {
        print("[CEFBridge] Navigating to: \(url)")

        url.absoluteString.withCString { urlCString in
            cef_navigate_to_url(handle, urlCString)
        }
    }

    /// Navigate back in history
    func goBack(handle: CefBrowserHandle) {
        print("[CEFBridge] Going back")
        cef_go_back(handle)
    }

    /// Navigate forward in history
    func goForward(handle: CefBrowserHandle) {
        print("[CEFBridge] Going forward")
        cef_go_forward(handle)
    }

    /// Reload the current page
    func reload(handle: CefBrowserHandle) {
        print("[CEFBridge] Reloading")
        cef_reload(handle)
    }

    /// Stop loading
    func stopLoading(handle: CefBrowserHandle) {
        print("[CEFBridge] Stopping load")
        cef_stop_loading(handle)
    }

    // MARK: - Browser State

    /// Check if the browser can go back
    func canGoBack(handle: CefBrowserHandle) -> Bool {
        return cef_can_go_back(handle) != 0
    }

    /// Check if the browser can go forward
    func canGoForward(handle: CefBrowserHandle) -> Bool {
        return cef_can_go_forward(handle) != 0
    }

    /// Check if the browser is loading
    func isLoading(handle: CefBrowserHandle) -> Bool {
        return cef_is_loading(handle) != 0
    }

    // MARK: - Editing Commands

    /// Copy selected text to clipboard
    func copy(handle: CefBrowserHandle) {
        cef_copy(handle)
    }

    /// Cut selected text to clipboard
    func cut(handle: CefBrowserHandle) {
        cef_cut(handle)
    }

    /// Paste from clipboard
    func paste(handle: CefBrowserHandle) {
        cef_paste(handle)
    }

    /// Select all text
    func selectAll(handle: CefBrowserHandle) {
        cef_select_all(handle)
    }

    /// Undo last action
    func undo(handle: CefBrowserHandle) {
        cef_undo(handle)
    }

    /// Redo last undone action
    func redo(handle: CefBrowserHandle) {
        cef_redo(handle)
    }

    /// Print the page
    func printPage(handle: CefBrowserHandle) {
        cef_print(handle)
    }

    // MARK: - View Management

    /// Resize the browser view
    /// - Parameters:
    ///   - handle: Browser handle
    ///   - size: New size
    func resize(handle: CefBrowserHandle, to size: CGSize) {
        print("[CEFBridge] Resizing to: \(Int(size.width))x\(Int(size.height))")
        cef_resize_browser(handle, Int32(size.width), Int32(size.height))
    }

    // MARK: - Data Management

    /// Clear all cookies
    func clearAllCookies() {
        print("[CEFBridge] Clearing all cookies")
        cef_delete_cookies(nil, nil)  // nil, nil means clear all
    }

    // MARK: - Message Loop

    /// Run a single iteration of the CEF message loop
    /// Call this periodically if not using CEF's built-in message loop
    /// - Returns: True if work was performed
    @discardableResult
    func doMessageLoopWork() -> Bool {
        return cef_do_message_work() != 0
    }
    // MARK: - Media Permissions
    // =============================================================================

    // Respond to a media permission request from a website
    // handle: The browser handle from the callback
    // allowedPermissions: Bitmask (1=audio, 2=video, 3=both)
    func respondToMediaPermission(handle: CefBrowserHandle, allowedPermissions: Int) {
        cef_respond_to_media_permission(handle, Int32(allowedPermissions))
    }
}
