// BrowserManager.swift - Persistent Browser State Engine
// Implements view reparenting pattern for CEF browser persistence
// Swift 6.2 with MainActor isolation

import AppKit
import CEFWrapper
import Foundation

// =============================================================================
// MARK: - Browser Manager (Persistent Store)
// =============================================================================

/// Singleton manager that keeps CEF browser instances alive across tab switches.
///
/// Architecture:
/// - Stores CEFContainerView instances keyed by tab UUID
/// - Browser views persist in memory even when not visible in SwiftUI hierarchy
/// - SwiftUI views act as "viewports" that reparent browser views as needed
/// - Prevents browser reload on tab switch by maintaining continuous browser lifecycle
///
/// Memory Management:
/// - Call `closeBrowser(for:)` when a tab is closed to destroy the CEF browser
/// - Browsers are NOT automatically destroyed when SwiftUI views are deallocated
@MainActor
final class BrowserManager {

    // MARK: - Singleton

    /// Shared singleton instance
    static let shared = BrowserManager()

    // MARK: - Properties

    /// Persistent storage for CEF browser host views, keyed by page UUID
    /// These views remain alive as long as the page exists
    private var browsers: [UUID: CEFContainerView] = [:]

    /// Weak reference to browser state for callbacks
    weak var browserState: BrowserState?

    // MARK: - Initialization

    private init() {
        print("[BrowserManager] Initialized")
    }

    // MARK: - Browser Lifecycle

    /// Get or create a browser view for a page
    /// - Parameters:
    ///   - pageId: The unique identifier for the page
    ///   - url: The initial URL to load (only used if creating new browser)
    ///   - delegate: CEF callback delegate for state updates
    ///   - parentTabId: Optional parent tab ID for opening child tabs
    /// - Returns: The persistent CEFContainerView for this page
    func getBrowser(
        for pageId: UUID,
        url: URL,
        delegate: (any CEFBrowserDelegate)?,
        parentTabId: UUID? = nil
    ) -> CEFContainerView {

        // Return existing browser if available
        if let existingView = browsers[pageId] {
            print("[BrowserManager] Returning existing browser for page \(pageId)")

            // Update delegate if provided (coordinator may have changed)
            if let delegate = delegate {
                existingView.updateDelegate(delegate)
            }

            return existingView
        }

        // Create new browser view for this page
        print("[BrowserManager] Creating new browser for page \(pageId) with URL: \(url)")

        let containerView = CEFContainerView(frame: .zero)
        containerView.identifier = NSUserInterfaceItemIdentifier("CEFBrowser-\(pageId.uuidString)")

        // CRITICAL: Set the pageId BEFORE loading URL or registering callbacks
        containerView.setPageId(pageId)

        // Set parent tab ID for child tab creation
        if let parentTabId = parentTabId {
            containerView.setParentTabId(parentTabId)
        }

        // Store in persistent dictionary BEFORE any async operations
        browsers[pageId] = containerView

        // Configure delegate and load URL
        if let delegate = delegate {
            containerView.coordinator = delegate
        }
        containerView.loadURL(url)

        return containerView
    }

    /// Check if a browser exists for a page
    /// - Parameter pageId: The page's unique identifier
    /// - Returns: True if a browser view exists for this page
    func hasBrowser(for pageId: UUID) -> Bool {
        return browsers[pageId] != nil
    }

    /// Get existing browser view without creating one
    /// - Parameter pageId: The page's unique identifier
    /// - Returns: The existing browser view, or nil if not found
    func existingBrowser(for pageId: UUID) -> CEFContainerView? {
        return browsers[pageId]
    }

    /// Close and destroy a browser for a page
    /// CRITICAL: Must be called when a page is removed to prevent memory leaks
    /// - Parameter pageId: The page's unique identifier
    func closeBrowser(for pageId: UUID) {
        guard let browserView = browsers[pageId] else {
            print("[BrowserManager] No browser to close for page \(pageId)")
            return
        }

        print("[BrowserManager] Closing browser for page \(pageId)")

        // Remove from parent if still attached
        browserView.removeFromSuperview()

        // Destroy the CEF browser instance
        browserView.destroyBrowser()

        // Remove from storage
        browsers.removeValue(forKey: pageId)

        print(
            "[BrowserManager] Browser destroyed for page \(pageId). Active browsers: \(browsers.count)"
        )
    }

    /// Close all browsers for multiple pages (batch cleanup)
    /// - Parameter pageIds: Array of page IDs to close
    func closeAllBrowsersForPages(pageIds: [UUID]) {
        for pageId in pageIds {
            closeBrowser(for: pageId)
        }
    }

    /// Close all browsers (called on app termination)
    func closeAllBrowsers() {
        print("[BrowserManager] Closing all browsers (\(browsers.count) active)")

        for (pageId, browserView) in browsers {
            browserView.removeFromSuperview()
            browserView.destroyBrowser()
            print("[BrowserManager] Destroyed browser for page \(pageId)")
        }

        browsers.removeAll()
        print("[BrowserManager] All browsers closed")
    }

    /// Navigate a specific page's browser to a new URL
    /// - Parameters:
    ///   - pageId: The page's unique identifier
    ///   - url: The URL to navigate to
    func navigate(pageId: UUID, to url: URL) {
        guard let browserView = browsers[pageId] else {
            print("[BrowserManager] No browser found for navigation: \(pageId)")
            return
        }

        print("[BrowserManager] Navigating page \(pageId) to: \(url)")
        browserView.loadURL(url)
    }

    /// Reload a specific page's browser
    /// - Parameter pageId: The page's unique identifier
    func reload(pageId: UUID) {
        guard let browserView = browsers[pageId] else { return }
        browserView.reload()
    }

    /// Recreate a browser to apply new settings (e.g., stack-mode toggle)
    /// This destroys the existing browser and creates a new one with the same URL
    /// but with updated settings based on the current page state.
    /// - Parameters:
    ///   - pageId: The page's unique identifier
    ///   - delegate: CEF callback delegate for state updates (optional)
    ///   - parentTabId: Optional parent tab ID for opening child tabs
    func recreateBrowser(
        for pageId: UUID, delegate: (any CEFBrowserDelegate)?, parentTabId: UUID? = nil
    ) {
        guard let existingBrowser = browsers[pageId] else {
            print("[BrowserManager] No browser to recreate for page \(pageId)")
            return
        }

        // Capture current state before destroying
        let currentURL = existingBrowser.currentURLString
        let url = URL(string: currentURL) ?? URL(string: "https://www.google.com")!

        print("[BrowserManager] Recreating browser for page \(pageId) with URL: \(url)")

        // Destroy existing browser
        existingBrowser.removeFromSuperview()
        existingBrowser.destroyBrowser()
        browsers.removeValue(forKey: pageId)

        // Create new browser with updated settings
        _ = getBrowser(
            for: pageId, url: url, delegate: delegate, parentTabId: parentTabId)

        print("[BrowserManager] Browser recreated successfully for page \(pageId)")
    }

    /// Go back in history for a specific page
    /// - Parameter pageId: The page's unique identifier
    func goBack(pageId: UUID) {
        guard let browserView = browsers[pageId] else { return }
        browserView.goBack()
    }

    /// Go forward in history for a specific page
    /// - Parameter pageId: The page's unique identifier
    func goForward(pageId: UUID) {
        guard let browserView = browsers[pageId] else { return }
        browserView.goForward()
    }

    /// Stop loading for a specific page
    /// - Parameter pageId: The page's unique identifier
    func stopLoading(pageId: UUID) {
        guard let browserView = browsers[pageId] else { return }
        browserView.stopLoading()
    }

    /// Set zoom level for a specific page
    /// - Parameters:
    ///   - pageId: The page's unique identifier
    ///   - level: The zoom level to set
    func setZoomLevel(pageId: UUID, level: Double) {
        guard let browserView = browsers[pageId] else { return }
        browserView.setZoomLevel(level)
    }

    /// Get zoom level for a specific page
    /// - Parameter pageId: The page's unique identifier
    /// - Returns: The current zoom level, or 0.0 if the browser is not found
    func getZoomLevel(pageId: UUID) -> Double {
        guard let browserView = browsers[pageId] else { return 0.0 }
        return browserView.getZoomLevel()
    }

    // MARK: - Editing Commands

    /// Copy selected text to clipboard
    /// - Parameter pageId: The page's unique identifier
    func copy(pageId: UUID) {
        guard let browserView = browsers[pageId], let handle = browserView.cefBrowserHandle else {
            return
        }
        CEFBridge.shared.copy(handle: handle)
    }

    /// Cut selected text to clipboard
    /// - Parameter pageId: The page's unique identifier
    func cut(pageId: UUID) {
        guard let browserView = browsers[pageId], let handle = browserView.cefBrowserHandle else {
            return
        }
        CEFBridge.shared.cut(handle: handle)
    }

    /// Paste from clipboard
    /// - Parameter pageId: The page's unique identifier
    func paste(pageId: UUID) {
        guard let browserView = browsers[pageId], let handle = browserView.cefBrowserHandle else {
            return
        }
        CEFBridge.shared.paste(handle: handle)
    }

    /// Select all text
    /// - Parameter pageId: The page's unique identifier
    func selectAll(pageId: UUID) {
        guard let browserView = browsers[pageId], let handle = browserView.cefBrowserHandle else {
            return
        }
        CEFBridge.shared.selectAll(handle: handle)
    }

    /// Undo last action
    /// - Parameter pageId: The page's unique identifier
    func undo(pageId: UUID) {
        guard let browserView = browsers[pageId], let handle = browserView.cefBrowserHandle else {
            return
        }
        CEFBridge.shared.undo(handle: handle)
    }

    /// Redo last undone action
    /// - Parameter pageId: The page's unique identifier
    func redo(pageId: UUID) {
        guard let browserView = browsers[pageId], let handle = browserView.cefBrowserHandle else {
            return
        }
        CEFBridge.shared.redo(handle: handle)
    }

    /// Print the page
    /// - Parameter pageId: The page's unique identifier
    func printPage(pageId: UUID) {
        guard let browserView = browsers[pageId], let handle = browserView.cefBrowserHandle else {
            return
        }
        CEFBridge.shared.printPage(handle: handle)
    }

    /// Capture snapshot for a specific page
    /// - Parameters:
    ///   - pageId: The page's unique identifier
    ///   - completion: Called with the snapshot image
    func captureSnapshot(pageId: UUID, completion: @escaping @MainActor (NSImage?) -> Void) {
        guard let browserView = browsers[pageId] else {
            completion(nil)
            return
        }
        browserView.captureSnapshot(completion: completion)
    }

    // MARK: - Debug

    /// Get count of active browsers
    var activeBrowserCount: Int {
        return browsers.count
    }

    /// Get list of active page IDs
    var activePageIds: [UUID] {
        return Array(browsers.keys)
    }

    // MARK: - New Tab Operations

    /// Open a new tab with the specified URL
    /// Creates a new TabModel, adds it to the tabs array, and sets it as active
    /// The CEF browser will be created lazily when the BrowserView renders
    /// - Parameter url: The URL to load in the new tab
    /// - Returns: The UUID of the newly created tab
    @discardableResult
    func openNewTab(with url: URL) -> UUID? {
        guard let state = browserState else {
            print("[BrowserManager] Cannot open new tab: browserState is nil")
            return nil
        }

        // Use createTab which properly delegates to TabManager
        state.createTab(url: url)

        // Get the ID of the newly created tab
        let newTabId = state.activeTab?.id

        state.addressBarText = url.absoluteString

        print("[BrowserManager] Opened new tab \(newTabId?.uuidString ?? "nil") with URL: \(url)")

        // The CEF browser will be created when BrowserView renders for this tab
        // via getBrowser() call in updateNSView

        return newTabId
    }
}
