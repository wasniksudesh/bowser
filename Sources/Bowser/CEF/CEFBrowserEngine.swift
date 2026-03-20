// CEFBrowserEngine.swift - CEF Implementation of BrowserEngineProtocol
// Wraps existing BrowserManager for backward compatibility
// Swift 6.2 with @MainActor isolation

import AppKit
import CEFWrapper
import Foundation

// =============================================================================
// MARK: - CEF Browser Engine
// =============================================================================

/// CEF implementation of BrowserEngineProtocol
/// Wraps existing BrowserManager and CEFBridge without modifying their internals
@MainActor
public final class CEFBrowserEngine: BrowserEngineProtocol, @unchecked Sendable {

    // MARK: - Properties

    /// Whether CEF has been initialized
    public private(set) var isInitialized: Bool = false

    /// Active browser handles keyed by tab UUID
    private var browsers: [UUID: BrowserHandle] = [:]

    /// Weak reference wrapper for delegates
    private final class WeakDelegate {
        weak var delegate: BrowserEngineDelegate?
        init(_ delegate: BrowserEngineDelegate) {
            self.delegate = delegate
        }
    }

    /// Registered delegates keyed by tab UUID
    private var delegates: [UUID: WeakDelegate] = [:]

    /// Adapter to bridge CEFBrowserDelegate to BrowserEngineDelegate
    private var adapters: [UUID: CEFDelegateAdapter] = [:]

    // MARK: - Initialization

    public init() {
        print("[CEFBrowserEngine] Initialized")
    }

    // MARK: - Lifecycle

    public func initialize() async -> Bool {
        guard !isInitialized else {
            print("[CEFBrowserEngine] Already initialized")
            return true
        }

        print("[CEFBrowserEngine] Initializing CEF via existing infrastructure...")

        // Use existing CEFBridge initialization
        let success = CEFBridge.shared.initialize()

        if success {
            isInitialized = true
            print("[CEFBrowserEngine] CEF initialized successfully")
        } else {
            print("[CEFBrowserEngine] CEF initialization failed")
        }

        return success
    }

    public func shutdown() async {
        guard isInitialized else { return }

        print("[CEFBrowserEngine] Shutting down...")

        // Clean up all browsers
        for (tabId, _) in browsers {
            BrowserManager.shared.closeBrowser(for: tabId)
        }
        browsers.removeAll()
        delegates.removeAll()
        adapters.removeAll()

        // Shutdown CEF
        CEFBridge.shared.shutdown()

        isInitialized = false
        print("[CEFBrowserEngine] Shutdown complete")
    }

    // MARK: - Browser Management

    public func createBrowser(id: UUID, url: URL, delegate: BrowserEngineDelegate?) async
        -> BrowserHandle?
    {
        guard isInitialized else {
            print("[CEFBrowserEngine] Cannot create browser - not initialized")
            return nil
        }

        print("[CEFBrowserEngine] Creating browser for tab \(id) with URL: \(url)")

        // Create delegate adapter if delegate provided
        var cefDelegate: CEFDelegateAdapter? = nil
        if let delegate = delegate {
            // Store weak reference
            delegates[id] = WeakDelegate(delegate)

            // Create adapter that bridges to BrowserEngineDelegate
            let adapter = CEFDelegateAdapter(tabId: id, engineDelegate: delegate)
            adapters[id] = adapter
            cefDelegate = adapter
        }

        // Use BrowserManager to create the browser
        // Note: BrowserManager creates browsers synchronously
        // For CEFBrowserEngine, id acts as both pageId and parentTabId (legacy pane mode)
        let _ = BrowserManager.shared.getBrowser(
            for: id, url: url, delegate: cefDelegate, parentTabId: id)

        // Create handle with a simple engineId based on the UUID hash
        let handle = BrowserHandle(id: id, engineId: Int64(id.hashValue))
        browsers[id] = handle

        print("[CEFBrowserEngine] Browser created with handle: \(handle)")
        return handle
    }

    public func destroyBrowser(_ handle: BrowserHandle) async {
        let tabId = handle.id

        print("[CEFBrowserEngine] Destroying browser for tab \(tabId)")

        // Clean up our tracking
        browsers.removeValue(forKey: tabId)
        delegates.removeValue(forKey: tabId)
        adapters.removeValue(forKey: tabId)

        // Delegate to BrowserManager
        BrowserManager.shared.closeBrowser(for: tabId)
    }

    public func getNativeView(for handle: BrowserHandle) -> NSView? {
        return BrowserManager.shared.existingBrowser(for: handle.id)
    }

    // MARK: - Navigation

    public func navigate(_ handle: BrowserHandle, to url: URL) async {
        print("[CEFBrowserEngine] Navigate \(handle.id) to \(url)")
        BrowserManager.shared.navigate(pageId: handle.id, to: url)
    }

    public func goBack(_ handle: BrowserHandle) async {
        BrowserManager.shared.goBack(pageId: handle.id)
    }

    public func goForward(_ handle: BrowserHandle) async {
        BrowserManager.shared.goForward(pageId: handle.id)
    }

    public func reload(_ handle: BrowserHandle) async {
        BrowserManager.shared.reload(pageId: handle.id)
    }

    public func stopLoading(_ handle: BrowserHandle) async {
        BrowserManager.shared.stopLoading(pageId: handle.id)
    }

    // MARK: - State Queries

    public func canGoBack(_ handle: BrowserHandle) -> Bool {
        // Query the CEFContainerView directly for state
        guard let browserView = BrowserManager.shared.existingBrowser(for: handle.id),
            let cefHandle = browserView.cefBrowserHandle
        else {
            return false
        }
        return cef_can_go_back(cefHandle) != 0
    }

    public func canGoForward(_ handle: BrowserHandle) -> Bool {
        guard let browserView = BrowserManager.shared.existingBrowser(for: handle.id),
            let cefHandle = browserView.cefBrowserHandle
        else {
            return false
        }
        return cef_can_go_forward(cefHandle) != 0
    }

    public func isLoading(_ handle: BrowserHandle) -> Bool {
        guard let browserView = BrowserManager.shared.existingBrowser(for: handle.id),
            let cefHandle = browserView.cefBrowserHandle
        else {
            return false
        }
        return cef_is_loading(cefHandle) != 0
    }

    public func currentURL(_ handle: BrowserHandle) -> URL? {
        guard let browserView = BrowserManager.shared.existingBrowser(for: handle.id) else {
            return nil
        }
        // CEFContainerView stores currentURLString
        return URL(string: browserView.currentURLString)
    }

    public func currentTitle(_ handle: BrowserHandle) -> String? {
        // Title is stored in BrowserState, not in CEFContainerView
        // Return nil as this is tracked at a higher level
        return nil
    }

    // MARK: - View Management

    public func resize(_ handle: BrowserHandle, to size: CGSize) async {
        guard let browserView = BrowserManager.shared.existingBrowser(for: handle.id),
            let cefHandle = browserView.cefBrowserHandle
        else {
            return
        }
        cef_resize_browser(cefHandle, Int32(size.width), Int32(size.height))
    }

    // MARK: - Snapshots

    public func captureSnapshot(_ handle: BrowserHandle) async -> NSImage? {
        guard let browserView = BrowserManager.shared.existingBrowser(for: handle.id) else {
            return nil
        }

        // Bridge callback-based API to async/await
        // Use an @unchecked Sendable wrapper to transfer the image safely
        // This is safe because the callback runs on MainActor and we're already on MainActor
        final class ImageBox: @unchecked Sendable {
            var image: NSImage?
        }

        let box = ImageBox()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            browserView.captureSnapshot { capturedImage in
                box.image = capturedImage
                continuation.resume()
            }
        }

        return box.image
    }

    // MARK: - Permissions

    public func respondToMediaPermission(_ handle: BrowserHandle, permissions: Int) async {
        guard let browserView = BrowserManager.shared.existingBrowser(for: handle.id),
            let cefHandle = browserView.cefBrowserHandle
        else {
            print("[CEFBrowserEngine] Cannot respond to permission - no handle")
            return
        }

        CEFBridge.shared.respondToMediaPermission(
            handle: cefHandle, allowedPermissions: permissions)
    }
}

// =============================================================================
// MARK: - CEF Delegate Adapter
// =============================================================================

/// Adapts CEFBrowserDelegate callbacks to BrowserEngineDelegate
/// Bridges the existing callback system to the new abstraction layer
@MainActor
final class CEFDelegateAdapter: NSObject, CEFBrowserDelegate {

    private let tabId: UUID
    private weak var engineDelegate: BrowserEngineDelegate?

    init(tabId: UUID, engineDelegate: BrowserEngineDelegate) {
        self.tabId = tabId
        self.engineDelegate = engineDelegate
        super.init()
    }

    private func createHandle() -> BrowserHandle {
        return BrowserHandle(id: tabId, engineId: Int64(tabId.hashValue))
    }

    // MARK: - CEFBrowserDelegate

    func browserDidChangeLoadingState(
        isLoading: Bool, canGoBack: Bool, canGoForward: Bool, url: URL?
    ) {
        engineDelegate?.engineDidChangeLoadingState(
            handle: createHandle(),
            isLoading: isLoading,
            canGoBack: canGoBack,
            canGoForward: canGoForward,
            url: url
        )
    }

    func browserDidChangeTitle(_ title: String) {
        engineDelegate?.engineDidChangeTitle(handle: createHandle(), title: title)
    }

    func browserDidChangeURL(_ url: URL) {
        engineDelegate?.engineDidChangeURL(handle: createHandle(), url: url)
    }

    func browserDidChangeFaviconURL(_ faviconURL: URL?) {
        engineDelegate?.engineDidChangeFaviconURL(handle: createHandle(), faviconURL: faviconURL)
    }

    func browserDidCapturePreview(_ preview: NSImage) {
        engineDelegate?.engineDidCapturePreview(handle: createHandle(), preview: preview)
    }

    func browserDidRequestMediaPermission(
        requestingOrigin: String, requestedPermissions: Int, handle: CefBrowserHandle
    ) {
        // Note: The handle passed here is the raw C handle, but createHandle() makes a logical handle
        // We pass the logical handle to the delegate, but keeping the association might be tricky
        // In the bridge, we use the raw handle to respond.
        // But the delegate only knows BrowserHandle.
        // We might need to store the mapping or just pass the logical handle and have the delegate use BrowserEngine to respond?
        // But CEFBridge.respondToMediaPermission takes CefBrowserHandle.
        // Solution: The delegate will decide, but the response mechanism needs the raw handle.
        // Since we can't easily pass CefBrowserHandle through the protocol (it's pure Swift),
        // we might need to handle the response IN THE ADAPTER if the delegate returns a synchronous decision,
        // OR we map the logical handle back to raw handle in CEFBrowserEngine/CEFBridge.

        // However, looking at CEFBridge, it tracks browsers by ObjectIdentifier(parentView) or similar?
        // Actually CEFBridge stores [ObjectIdentifier: CefBrowserHandle].
        // And CEFBrowserEngine stores [UUID: BrowserHandle].

        // For now, let's pass the logical handle and origin to the delegate.
        // The delegate will update Settings/UI.
        // To RESPOND, the delegate should tell the Engine to allow/deny.
        // But the Engine needs the raw handle.
        // The CEFBridge callback handles response via `cef_respond_to_media_permission`.
        // If we want to support async response from UI, we need to hold the raw handle somewhere.
        // But `CEFCallbackBridge` holds the pending callback in C++ map `g_pending_permission_callbacks`.
        // So we just need the raw handle pointer address to identify the callback.

        // Wait, BrowserHandle.engineId is Int64(id.hashValue). It doesn't store the raw pointer.
        // We might need to enhance BrowserHandle or look up the raw handle.
        // But for now, let's assume we can look it up or we only support synchronous global settings.

        engineDelegate?.engineDidRequestMediaPermission(
            handle: createHandle(),
            origin: requestingOrigin,
            permissions: requestedPermissions
        )
    }
}
