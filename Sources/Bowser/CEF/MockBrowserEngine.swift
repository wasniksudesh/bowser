// MockBrowserEngine.swift - Mock Implementation for Testing
// Tracks method calls and returns sensible defaults
// Swift 6.2 with @MainActor isolation

import AppKit
import Foundation

// =============================================================================
// MARK: - Mock Browser Engine
// =============================================================================

/// Mock implementation of BrowserEngineProtocol for testing
/// Tracks all method calls and returns configurable defaults
@MainActor
public final class MockBrowserEngine: BrowserEngineProtocol, @unchecked Sendable {

    // MARK: - Tracking Properties

    /// Whether initialize() was called
    public private(set) var initializeCalled = false

    /// Whether shutdown() was called
    public private(set) var shutdownCalled = false

    /// List of browser IDs that were created
    public private(set) var createdBrowsers: [UUID] = []

    /// List of browser IDs that were destroyed
    public private(set) var destroyedBrowsers: [UUID] = []

    /// List of URLs that were navigated to, keyed by browser ID
    public private(set) var navigatedURLs: [UUID: [URL]] = [:]

    /// Count of goBack calls
    public private(set) var goBackCount = 0

    /// Count of goForward calls
    public private(set) var goForwardCount = 0

    /// Count of reload calls
    public private(set) var reloadCount = 0

    /// Count of stopLoading calls
    public private(set) var stopLoadingCount = 0

    /// Count of snapshot captures
    public private(set) var snapshotCount = 0

    /// List of permission responses
    public private(set) var permissionResponses: [(UUID, Int)] = []

    // MARK: - Configurable Behavior

    /// Whether initialize() should succeed
    public var initializeShouldSucceed = true

    /// Whether createBrowser() should succeed
    public var createBrowserShouldSucceed = true

    /// Mock values for state queries
    public var mockCanGoBack = false
    public var mockCanGoForward = false
    public var mockIsLoading = false
    public var mockCurrentURL: URL? = nil
    public var mockCurrentTitle: String? = nil
    public var mockSnapshot: NSImage? = nil

    // MARK: - Internal State

    public private(set) var isInitialized: Bool = false
    private var browsers: [UUID: BrowserHandle] = [:]

    // MARK: - Initialization

    public init() {
        print("[MockBrowserEngine] Initialized")
    }

    /// Reset all tracking and state for fresh test runs
    public func reset() {
        initializeCalled = false
        shutdownCalled = false
        createdBrowsers = []
        destroyedBrowsers = []
        navigatedURLs = [:]
        goBackCount = 0
        goForwardCount = 0
        reloadCount = 0
        stopLoadingCount = 0
        snapshotCount = 0
        isInitialized = false
        browsers = [:]
    }

    // MARK: - Lifecycle

    public func initialize() async -> Bool {
        initializeCalled = true

        if initializeShouldSucceed {
            isInitialized = true
            print("[MockBrowserEngine] Initialize called (success)")
            return true
        } else {
            print("[MockBrowserEngine] Initialize called (failed)")
            return false
        }
    }

    public func shutdown() async {
        shutdownCalled = true
        isInitialized = false
        browsers.removeAll()
        print("[MockBrowserEngine] Shutdown called")
    }

    // MARK: - Browser Management

    public func createBrowser(id: UUID, url: URL, delegate: BrowserEngineDelegate?) async
        -> BrowserHandle?
    {
        createdBrowsers.append(id)

        if !createBrowserShouldSucceed {
            print("[MockBrowserEngine] createBrowser failed (configured)")
            return nil
        }

        let handle = BrowserHandle(id: id, engineId: Int64(id.hashValue))
        browsers[id] = handle

        // Track initial URL
        navigatedURLs[id] = [url]

        print("[MockBrowserEngine] createBrowser: \(id) with URL: \(url)")
        return handle
    }

    public func destroyBrowser(_ handle: BrowserHandle) async {
        destroyedBrowsers.append(handle.id)
        browsers.removeValue(forKey: handle.id)
        print("[MockBrowserEngine] destroyBrowser: \(handle.id)")
    }

    public func getNativeView(for handle: BrowserHandle) -> NSView? {
        // Return a simple NSView for testing
        if browsers[handle.id] != nil {
            return NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        }
        return nil
    }

    // MARK: - Navigation

    public func navigate(_ handle: BrowserHandle, to url: URL) async {
        var urls = navigatedURLs[handle.id] ?? []
        urls.append(url)
        navigatedURLs[handle.id] = urls
        print("[MockBrowserEngine] navigate: \(handle.id) to \(url)")
    }

    public func goBack(_ handle: BrowserHandle) async {
        goBackCount += 1
        print("[MockBrowserEngine] goBack: \(handle.id)")
    }

    public func goForward(_ handle: BrowserHandle) async {
        goForwardCount += 1
        print("[MockBrowserEngine] goForward: \(handle.id)")
    }

    public func reload(_ handle: BrowserHandle) async {
        reloadCount += 1
        print("[MockBrowserEngine] reload: \(handle.id)")
    }

    public func stopLoading(_ handle: BrowserHandle) async {
        stopLoadingCount += 1
        print("[MockBrowserEngine] stopLoading: \(handle.id)")
    }

    // MARK: - State Queries

    public func canGoBack(_ handle: BrowserHandle) -> Bool {
        return mockCanGoBack
    }

    public func canGoForward(_ handle: BrowserHandle) -> Bool {
        return mockCanGoForward
    }

    public func isLoading(_ handle: BrowserHandle) -> Bool {
        return mockIsLoading
    }

    public func currentURL(_ handle: BrowserHandle) -> URL? {
        return mockCurrentURL ?? navigatedURLs[handle.id]?.last
    }

    public func currentTitle(_ handle: BrowserHandle) -> String? {
        return mockCurrentTitle
    }

    // MARK: - View Management

    public func resize(_ handle: BrowserHandle, to size: CGSize) async {
        print("[MockBrowserEngine] resize: \(handle.id) to \(size)")
    }

    // MARK: - Snapshots

    public func captureSnapshot(_ handle: BrowserHandle) async -> NSImage? {
        snapshotCount += 1
        print("[MockBrowserEngine] captureSnapshot: \(handle.id)")
        return mockSnapshot
    }

    // MARK: - Permissions

    public func respondToMediaPermission(_ handle: BrowserHandle, permissions: Int) async {
        permissionResponses.append((handle.id, permissions))
        print("[MockBrowserEngine] respondToMediaPermission: \(handle.id) -> \(permissions)")
    }
}
