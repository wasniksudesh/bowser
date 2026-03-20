// CEFCallbackBridge.swift - C++ to Swift Callback Bridge
// Handles CEF callbacks from background thread and dispatches to MainActor
// Swift 6.2 with proper Sendable compliance

import AppKit
import CEFWrapper
import Foundation

// =============================================================================
// MARK: - Browser Delegate Protocol
// =============================================================================

/// Protocol for receiving CEF browser state updates
/// All methods are called on MainActor after being dispatched from CEF background thread
@MainActor
protocol CEFBrowserDelegate: AnyObject {

    /// Called when the loading state changes
    /// - Parameters:
    ///   - isLoading: True if the page is currently loading
    ///   - canGoBack: True if browser can navigate back in history
    ///   - canGoForward: True if browser can navigate forward in history
    ///   - url: The URL being loaded
    func browserDidChangeLoadingState(
        isLoading: Bool, canGoBack: Bool, canGoForward: Bool, url: URL?)

    /// Called when the page title changes
    /// - Parameter title: The new page title
    func browserDidChangeTitle(_ title: String)

    /// Called when the URL changes (navigation)
    /// - Parameter url: The new URL
    func browserDidChangeURL(_ url: URL)

    /// Called when the favicon URL changes
    /// - Parameter faviconURL: The URL of the favicon (nil if no favicon available)
    func browserDidChangeFaviconURL(_ faviconURL: URL?)

    /// Called when a tab preview snapshot is ready (Capture-on-Load strategy)
    /// This is called automatically ~500ms after page load completes
    /// - Parameter preview: The captured preview image
    func browserDidCapturePreview(_ preview: NSImage)

    /// Called when user selects "Open Link as Child Tab" from right-click menu
    /// - Parameters:
    ///   - url: The URL of the link to open as child tab
    ///   - parentTabId: The tab ID that should be the parent of the new tab (the tab that owns this browser)
    func browserDidRequestOpenLinkAsChildTab(_ url: URL, parentTabId: UUID)

    /// Called when a website requests camera/microphone access
    /// - Parameters:
    ///   - requestingOrigin: The URL origin requesting permission (e.g., "https://example.com")
    ///   - requestedPermissions: Bitfield of requested permissions (1=audio, 2=video, 3=both)
    ///   - handle: The browser handle to respond to
    func browserDidRequestMediaPermission(
        requestingOrigin: String, requestedPermissions: Int, handle: CefBrowserHandle)

    /// Called when user clicks a link (before navigation)
    /// - Parameters:
    ///   - url: The URL of the link that was clicked
    /// - Returns: True to allow navigation, false to cancel (for stack mode)
    func browserDidRequestLinkNavigation(_ url: URL) -> Bool

    // MARK: - Legacy Callbacks (for CEFContainerView compatibility)

    /// Called when page starts loading (legacy callback)
    func onLoadStart(url: URL)

    /// Called when navigation state changes (legacy callback)
    func onNavigationStateChange(canGoBack: Bool, canGoForward: Bool)
}

// Default implementations for optional legacy methods
extension CEFBrowserDelegate {
    func onLoadStart(url: URL) {
        // Default: delegate to browserDidChangeLoadingState
        browserDidChangeLoadingState(
            isLoading: true, canGoBack: false, canGoForward: false, url: url)
    }

    func onNavigationStateChange(canGoBack: Bool, canGoForward: Bool) {
        // Default: no-op (implemented by coordinators that need it)
    }

    func browserDidRequestOpenLinkAsChildTab(_ url: URL, parentTabId: UUID) {
        // Default: no-op (implemented by coordinators that need it)
    }

    func browserDidRequestMediaPermission(
        requestingOrigin: String, requestedPermissions: Int, handle: CefBrowserHandle
    ) {
        // Default: no-op (implemented by coordinators that need it)
    }

    func browserDidRequestLinkNavigation(_ url: URL) -> Bool {
        // Default: allow navigation
        return true
    }
}

// =============================================================================
// MARK: - Callback Registry
// =============================================================================

/// Thread-safe registry mapping browser handles to Swift delegates and tab IDs
/// Uses NSLock for thread safety since callbacks come from CEF UI thread
///
/// CRITICAL: Each browser handle is associated with both a delegate AND a tabId.
/// The tabId represents the tab that OWNS this browser instance (set at browser creation).
/// This ensures correct parent identification when creating child tabs, even if the
/// delegate's internal state has changed (e.g., when SplitPaneViewController switches tabs).
final class CEFCallbackRegistry: @unchecked Sendable {

    /// Shared singleton instance
    static let shared = CEFCallbackRegistry()

    /// Lock for thread-safe access
    private let lock = NSLock()

    /// Registration data (browser handle -> delegate + tabId)
    /// Using UnsafeRawPointer as key (non-optional)
    private var registrations: [UnsafeRawPointer: BrowserRegistration] = [:]

    /// Wrapper to hold delegate and tab ID for a browser
    private final class BrowserRegistration {
        weak var delegate: (any CEFBrowserDelegate)?
        let tabId: UUID
        var isStackMode: Bool = false

        init(delegate: any CEFBrowserDelegate, tabId: UUID) {
            self.delegate = delegate
            self.tabId = tabId
        }
    }

    private init() {}

    // MARK: - Registration

    /// Register a delegate and tab ID for a browser handle
    /// - Parameters:
    ///   - delegate: The delegate to receive callbacks
    ///   - handle: The CEF browser handle (non-nil)
    ///   - tabId: The tab ID that owns this browser (used for parent identification)
    func register(delegate: any CEFBrowserDelegate, for handle: UnsafeRawPointer, tabId: UUID) {
        lock.lock()
        defer { lock.unlock() }

        registrations[handle] = BrowserRegistration(delegate: delegate, tabId: tabId)
        // Default to false, can be updated later
        print("[CEFCallbackBridge] Registered delegate for handle: \(handle), tabId: \(tabId)")
    }

    /// Update just the delegate for a browser handle (keeps the same tabId)
    /// Used when reparenting a browser view to a different pane
    /// - Parameters:
    ///   - delegate: The new delegate to receive callbacks
    ///   - handle: The CEF browser handle (non-nil)
    func updateDelegate(_ delegate: any CEFBrowserDelegate, for handle: UnsafeRawPointer) {
        lock.lock()
        defer { lock.unlock() }

        if let existing = registrations[handle] {
            // Keep the original tabId and stack mode, just update the delegate
            let newInit = BrowserRegistration(delegate: delegate, tabId: existing.tabId)
            newInit.isStackMode = existing.isStackMode
            registrations[handle] = newInit
            print(
                "[CEFCallbackBridge] Updated delegate for handle: \(handle), tabId preserved: \(existing.tabId), stackMode: \(existing.isStackMode)"
            )
        } else {
            print(
                "[CEFCallbackBridge] WARNING: Tried to update delegate for unregistered handle: \(handle)"
            )
        }
    }

    /// Update the stack mode state for a browser handle
    /// - Parameters:
    ///   - isStackMode: Whether stack mode is enabled (cancels navigation)
    ///   - handle: The CEF browser handle (non-nil)
    func setStackMode(_ isStackMode: Bool, for handle: UnsafeRawPointer) {
        lock.lock()
        defer { lock.unlock() }

        if let registration = registrations[handle] {
            registration.isStackMode = isStackMode
            print(
                "[CEFCallbackBridge] Set stack mode to \(isStackMode) for handle: \(handle)"
            )
        } else {
            print(
                "[CEFCallbackBridge] WARNING: Tried to set stack mode for unregistered handle: \(handle)"
            )
        }
    }

    /// Unregister a delegate for a browser handle
    /// - Parameter handle: The CEF browser handle (non-nil)
    func unregister(handle: UnsafeRawPointer) {
        lock.lock()
        defer { lock.unlock() }

        registrations.removeValue(forKey: handle)
        print("[CEFCallbackBridge] Unregistered delegate for handle: \(handle)")
    }

    /// Get delegate for a browser handle (called from callback)
    /// - Parameter handle: The CEF browser handle (non-nil)
    /// - Returns: The registered delegate, or nil if not found
    func delegate(for handle: UnsafeRawPointer) -> (any CEFBrowserDelegate)? {
        lock.lock()
        defer { lock.unlock() }

        return registrations[handle]?.delegate
    }

    /// Get the tab ID for a browser handle (called from callback)
    /// - Parameter handle: The CEF browser handle (non-nil)
    /// - Returns: The tab ID that owns this browser, or nil if not found
    func tabId(for handle: UnsafeRawPointer) -> UUID? {
        lock.lock()
        defer { lock.unlock() }

        return registrations[handle]?.tabId
    }

    /// Check if stack mode is enabled for a browser handle (synchronous)
    /// - Parameter handle: The CEF browser handle (non-nil)
    /// - Returns: True if stack mode is enabled
    func isStackMode(for handle: UnsafeRawPointer) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return registrations[handle]?.isStackMode ?? false
    }
}

// =============================================================================
// MARK: - C Callback Functions
// =============================================================================

/// Sendable wrapper for UnsafeRawPointer to safely cross isolation boundaries
/// Used to pass CEF browser handles from C callbacks to MainActor
struct SendableHandle: @unchecked Sendable {
    let pointer: UnsafeRawPointer

    init(_ pointer: UnsafeRawPointer) {
        self.pointer = pointer
    }
}

/// Global C callback for load state changes
/// IMPORTANT: This is called on the CEF UI thread (background)
/// We dispatch to MainActor before touching any UI state
private let loadStateCallback: CefLoadStateCallback = {
    handle, isLoading, canGoBack, canGoForward, urlCString in
    // Handle can be nil from C - guard against that
    guard let handle = handle else {
        print("[CEFCallbackBridge] Load state callback received nil handle")
        return
    }

    // Wrap handle in Sendable type for safe transfer across isolation boundaries
    let sendableHandle = SendableHandle(handle)

    // Capture values before async dispatch
    let isLoadingBool = isLoading != 0
    let canGoBackBool = canGoBack != 0
    let canGoForwardBool = canGoForward != 0
    let urlString = urlCString != nil ? String(cString: urlCString!) : nil

    // Dispatch to MainActor for UI updates
    // Using Task ensures we're on the main actor
    Task { @MainActor in
        guard let delegate = CEFCallbackRegistry.shared.delegate(for: sendableHandle.pointer) else {
            print("[CEFCallbackBridge] No delegate for load state callback")
            return
        }

        let url = urlString.flatMap { URL(string: $0) }
        delegate.browserDidChangeLoadingState(
            isLoading: isLoadingBool, canGoBack: canGoBackBool, canGoForward: canGoForwardBool,
            url: url)
    }
}

/// Global C callback for title changes
/// IMPORTANT: This is called on the CEF UI thread (background)
private let titleChangeCallback: CefTitleChangeCallback = { handle, titleCString in
    // Handle can be nil from C - guard against that
    guard let handle = handle else {
        print("[CEFCallbackBridge] Title change callback received nil handle")
        return
    }

    // Wrap handle in Sendable type for safe transfer across isolation boundaries
    let sendableHandle = SendableHandle(handle)

    // Capture title before async dispatch
    let title = titleCString != nil ? String(cString: titleCString!) : ""

    // Dispatch to MainActor for UI updates
    Task { @MainActor in
        guard let delegate = CEFCallbackRegistry.shared.delegate(for: sendableHandle.pointer) else {
            print("[CEFCallbackBridge] No delegate for title change callback")
            return
        }

        delegate.browserDidChangeTitle(title)
    }
}

/// Global C callback for URL changes
/// IMPORTANT: This is called on the CEF UI thread (background)
private let urlChangeCallback: CefUrlChangeCallback = { handle, urlCString in
    // Handle can be nil from C - guard against that
    guard let handle = handle else {
        print("[CEFCallbackBridge] URL change callback received nil handle")
        return
    }

    // Wrap handle in Sendable type for safe transfer across isolation boundaries
    let sendableHandle = SendableHandle(handle)

    // Capture URL before async dispatch
    let urlString = urlCString != nil ? String(cString: urlCString!) : nil

    // Dispatch to MainActor for UI updates
    Task { @MainActor in
        guard let delegate = CEFCallbackRegistry.shared.delegate(for: sendableHandle.pointer) else {
            print("[CEFCallbackBridge] No delegate for URL change callback")
            return
        }

        guard let urlString = urlString, let url = URL(string: urlString) else {
            return
        }

        delegate.browserDidChangeURL(url)
    }
}

/// Global C callback for favicon URL changes
/// IMPORTANT: This is called on the CEF UI thread (background)
private let faviconUrlChangeCallback: CefFaviconUrlChangeCallback = { handle, faviconUrlCString in
    // Handle can be nil from C - guard against that
    guard let handle = handle else {
        print("[CEFCallbackBridge] Favicon URL change callback received nil handle")
        return
    }

    // Wrap handle in Sendable type for safe transfer across isolation boundaries
    let sendableHandle = SendableHandle(handle)

    // Capture URL before async dispatch (empty string means no favicon)
    let faviconUrlString = faviconUrlCString != nil ? String(cString: faviconUrlCString!) : nil

    // Dispatch to MainActor for UI updates
    Task { @MainActor in
        guard let delegate = CEFCallbackRegistry.shared.delegate(for: sendableHandle.pointer) else {
            print("[CEFCallbackBridge] No delegate for favicon URL change callback")
            return
        }

        // Convert to URL, treating empty string as nil (triggers fallback)
        let faviconURL: URL?
        if let urlString = faviconUrlString, !urlString.isEmpty {
            faviconURL = URL(string: urlString)
        } else {
            faviconURL = nil
        }

        delegate.browserDidChangeFaviconURL(faviconURL)
    }
}

/// Global C callback for snapshot ready (Capture-on-Load strategy)
/// IMPORTANT: This is called on the CEF UI thread (background)
/// Receives RGBA pixel data and converts to NSImage before dispatching to MainActor
private let snapshotReadyCallback: CefSnapshotReadyCallback = {
    handle, buffer, width, height, bufferSize in
    // Handle can be nil from C - guard against that
    guard let handle = handle else {
        print("[CEFCallbackBridge] Snapshot ready callback received nil handle")
        return
    }

    guard let buffer = buffer, width > 0, height > 0, bufferSize > 0 else {
        print(
            "[CEFCallbackBridge] Snapshot ready callback received invalid data: \(width)x\(height), \(bufferSize) bytes"
        )
        return
    }

    print("[CEFCallbackBridge] Snapshot ready: \(width)x\(height), \(bufferSize) bytes")

    // Copy the buffer data immediately (it's only valid during this callback)
    let data = Data(bytes: buffer, count: bufferSize)

    // Wrap handle in Sendable type for safe transfer
    let sendableHandle = SendableHandle(handle)
    let imgWidth = Int(width)
    let imgHeight = Int(height)

    // Dispatch to MainActor for UI updates
    Task { @MainActor in
        guard let delegate = CEFCallbackRegistry.shared.delegate(for: sendableHandle.pointer) else {
            print("[CEFCallbackBridge] No delegate for snapshot ready callback")
            return
        }

        // Convert RGBA data to NSImage
        guard let image = createNSImage(from: data, width: imgWidth, height: imgHeight) else {
            print("[CEFCallbackBridge] Failed to create NSImage from snCanapshot data")
            return
        }

        print("[CEFCallbackBridge] Created NSImage: \(image.size.width)x\(image.size.height)")
        delegate.browserDidCapturePreview(image)
    }
}

/// Global C callback for media permission requests
/// IMPORTANT: This is called on the CEF UI thread (background)
private let mediaPermissionRequestCallback: CefMediaPermissionRequestCallback = {
    handle, originCString, requestedPermissions in
    // Handle can be nil from C - guard against that
    guard let handle = handle else {
        print("[CEFCallbackBridge] Media permission callback received nil handle")
        return
    }

    // Wrap handle in Sendable type for safe transfer across isolation boundaries
    let sendableHandle = SendableHandle(handle)

    // Capture values before async dispatch
    let origin = originCString != nil ? String(cString: originCString!) : ""
    let permissions = Int(requestedPermissions)

    // Dispatch to MainActor for UI updates
    Task { @MainActor in
        guard let delegate = CEFCallbackRegistry.shared.delegate(for: sendableHandle.pointer) else {
            print("[CEFCallbackBridge] No delegate for media permission callback")
            // Deny by default if no delegate
            cef_respond_to_media_permission(
                UnsafeMutableRawPointer(mutating: sendableHandle.pointer), 0)
            return
        }

        print(
            "[CEFCallbackBridge] Media permission requested: origin=\(origin), permissions=0x\(String(permissions, radix: 16))"
        )
        delegate.browserDidRequestMediaPermission(
            requestingOrigin: origin, requestedPermissions: permissions,
            handle: UnsafeMutableRawPointer(mutating: sendableHandle.pointer))
    }
}

/// Global C callback for "Open Link as Child Tab" context menu action
/// IMPORTANT: This is called on the CEF UI thread (background)
private let openLinkAsChildTabCallback: CefOpenLinkAsChildTabCallback = { handle, urlCString in
    // Handle can be nil from C - guard against that
    guard let handle = handle else {
        print("[CEFCallbackBridge] Open link as child tab callback received nil handle")
        return
    }

    // Wrap handle in Sendable type for safe transfer across isolation boundaries
    let sendableHandle = SendableHandle(handle)

    // Capture URL before async dispatch
    let urlString = urlCString != nil ? String(cString: urlCString!) : nil

    // Dispatch to MainActor for UI updates
    Task { @MainActor in
        guard let delegate = CEFCallbackRegistry.shared.delegate(for: sendableHandle.pointer) else {
            print("[CEFCallbackBridge] No delegate for open link as child tab callback")
            return
        }

        // CRITICAL: Get the tab ID that OWNS this browser instance
        // This is the correct parent for any child tabs opened from this browser
        guard let parentTabId = CEFCallbackRegistry.shared.tabId(for: sendableHandle.pointer) else {
            print(
                "[CEFCallbackBridge] No tabId registered for browser handle - cannot determine parent"
            )
            return
        }

        guard let urlString = urlString, let url = URL(string: urlString) else {
            print("[CEFCallbackBridge] Invalid URL for open link as child tab")
            return
        }

        print("[CEFCallbackBridge] Opening link as child tab: \(url), parentTabId: \(parentTabId)")
        delegate.browserDidRequestOpenLinkAsChildTab(url, parentTabId: parentTabId)
    }
}

/// Global C callback for link clicks (for stack mode interception)
/// IMPORTANT: This is called on the CEF UI thread (background)
/// Returns 1 to allow navigation, 0 to cancel
/// Global C callback for link clicks (for stack mode interception)
/// IMPORTANT: This is called on the CEF UI thread (background)
/// Returns 1 to allow navigation, 0 to cancel
private let linkClickCallback: CefLinkClickCallback = { handle, urlCString in
    // Handle can be nil from C - guard against that
    guard let handle = handle else {
        print("[CEFCallbackBridge] Link click callback received nil handle")
        return 1  // Allow by default
    }

    // Wrap handle in Sendable type for safe transfer across isolation boundaries
    let sendableHandle = SendableHandle(handle)

    // Capture URL
    let urlString = urlCString != nil ? String(cString: urlCString!) : nil

    // CRITICAL FIX: Check registry state SYNCHRONOUSLY
    // This avoids hopping to MainActor and waiting (which causes timeouts)
    let isStackMode = CEFCallbackRegistry.shared.isStackMode(for: sendableHandle.pointer)

    if isStackMode {
        print("[CEFCallbackBridge] 🛑 Stack Mode Active: Cancelling navigation synchronously")

        // Fire-and-forget notification to Swift to open new tab
        // We don't wait for this
        if let urlString = urlString {
            Task { @MainActor in
                guard
                    let delegate = CEFCallbackRegistry.shared.delegate(for: sendableHandle.pointer)
                else {
                    return
                }

                if let url = URL(string: urlString) {
                    print("[CEFCallbackBridge] ⚡️ Notifying delegate of blocked navigation: \(url)")
                    _ = delegate.browserDidRequestLinkNavigation(url)
                }
            }
        }

        return 0  // Cancel navigation
    } else {
        // Normal mode - allow navigation
        return 1
    }
}

/// Helper function to create NSImage from RGBA pixel data
/// - Parameters:
///   - data: RGBA pixel data (4 bytes per pixel)
///   - width: Image width in pixels
///   - height: Image height in pixels
/// - Returns: NSImage or nil on failure
@MainActor
private func createNSImage(from data: Data, width: Int, height: Int) -> NSImage? {
    guard width > 0, height > 0, data.count >= width * height * 4 else {
        return nil
    }

    // Create bitmap representation from RGBA data
    guard
        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        )
    else {
        return nil
    }

    // Copy pixel data into the bitmap
    guard let bitmapData = bitmapRep.bitmapData else {
        return nil
    }

    data.copyBytes(to: bitmapData, count: min(data.count, width * height * 4))

    // Create NSImage and add the representation
    let image = NSImage(size: NSSize(width: width, height: height))
    image.addRepresentation(bitmapRep)

    return image
}

// =============================================================================
// MARK: - CEF Callback Bridge
// =============================================================================

/// Bridge class to manage CEF callback registration
/// Provides a clean API for Swift code to set up callbacks
@MainActor
final class CEFCallbackBridge {

    /// Register callbacks for a browser handle with a delegate and tab ID
    /// - Parameters:
    ///   - handle: The CEF browser handle from cef_create_browser (optional - nil is ignored)
    ///   - delegate: The delegate to receive callbacks
    ///   - tabId: The tab ID that owns this browser (used for correct parent identification in child tabs)
    static func registerCallbacks(
        for handle: CefBrowserHandle?, delegate: any CEFBrowserDelegate, tabId: UUID
    ) {
        guard let handle = handle else {
            print("[CEFCallbackBridge] Cannot register callbacks - handle is nil")
            return
        }

        // Register delegate AND tabId in our registry
        CEFCallbackRegistry.shared.register(delegate: delegate, for: handle, tabId: tabId)

        // Register C callbacks with CEF (including snapshot callback for Capture-on-Load)
        cef_register_callbacks(
            handle,
            loadStateCallback,
            titleChangeCallback,
            urlChangeCallback,
            faviconUrlChangeCallback,
            snapshotReadyCallback,
            openLinkAsChildTabCallback,
            mediaPermissionRequestCallback,
            linkClickCallback
        )

        print(
            "[CEFCallbackBridge] Callbacks registered for browser handle: \(handle), tabId: \(tabId)"
        )
    }

    /// Update the delegate for an existing browser handle (preserves tabId)
    /// Used when reparenting a browser to a different pane
    /// - Parameters:
    ///   - handle: The CEF browser handle (optional - nil is ignored)
    ///   - delegate: The new delegate to receive callbacks
    static func updateDelegate(for handle: CefBrowserHandle?, delegate: any CEFBrowserDelegate) {
        guard let handle = handle else {
            print("[CEFCallbackBridge] Cannot update delegate - handle is nil")
            return
        }

        // Update just the delegate, keeping the original tabId and stack mode
        CEFCallbackRegistry.shared.updateDelegate(delegate, for: handle)
        print("[CEFCallbackBridge] Delegate updated for browser handle: \(handle)")
    }

    /// Set the stack mode state for a browser handle
    /// - Parameters:
    ///   - isStackMode: Whether stack mode is enabled
    ///   - handle: The CEF browser handle (optional - nil is ignored)
    static func setStackMode(_ isStackMode: Bool, for handle: CefBrowserHandle?) {
        guard let handle = handle else { return }
        CEFCallbackRegistry.shared.setStackMode(isStackMode, for: handle)
    }

    /// Unregister callbacks for a browser handle
    /// - Parameter handle: The CEF browser handle (optional - nil is ignored)
    static func unregisterCallbacks(for handle: CefBrowserHandle?) {
        guard let handle = handle else { return }

        // Remove from our registry
        CEFCallbackRegistry.shared.unregister(handle: handle)

        // Unregister from CEF (optional - cef_destroy_browser does this too)
        cef_unregister_callbacks(handle)

        print("[CEFCallbackBridge] Callbacks unregistered for browser handle: \(handle)")
    }
}
