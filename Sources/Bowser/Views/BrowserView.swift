// BrowserView.swift - CEF Browser Container with View Reparenting
// NSViewRepresentable bridging CEF to SwiftUI with persistent browser instances

import AppKit
import CEFWrapper
import Combine
import SwiftUI

// =============================================================================
// MARK: - Browser Canvas (Reparenting Bridge)
// =============================================================================

/// NSViewRepresentable that acts as a viewport for persistent CEF browser instances.
///
/// Architecture (View Reparenting Pattern):
/// - makeNSView: Returns an empty container NSView (viewport)
/// - updateNSView: Reparents the actual CEF browser view from BrowserManager
/// - Browser instances are NOT destroyed when SwiftUI destroys this view
/// - BrowserManager holds browsers persistently keyed by page UUID
///
/// This solves the page reload bug by keeping CEF browsers alive across page switches.
struct BrowserCanvas: NSViewRepresentable {

    /// Browser state for navigation and lifecycle (NOT @Bindable to prevent favicon update loops)
    var browserState: BrowserState

    /// The specific page ID this canvas should display
    /// When this changes, we reparent the corresponding browser view
    let pageId: UUID

    /// The parent tab ID for opening child tabs
    let parentTabId: UUID

    /// The URL to display - passed explicitly to control when updateNSView is called
    /// Only URL changes should trigger updates, not favicon/icon changes
    let url: URL

    // MARK: - NSViewRepresentable

    func makeNSView(context: Context) -> BrowserContainerView {
        // Create empty container view (viewport)
        let container = BrowserContainerView()
        container.identifier = NSUserInterfaceItemIdentifier("BrowserCanvas-\(pageId.uuidString)")
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        print("[BrowserCanvas] Created viewport container for page \(pageId)")

        // Subscribe to navigation notifications
        context.coordinator.subscribeToNotifications()

        // Setup gesture callback for stack mode
        let coordinator = context.coordinator
        container.onHorizontalPan = { [weak coordinator] state, translation, velocity in
            coordinator?.handleStackGesture(
                state: state, translation: translation, velocity: velocity)
        }

        return container
    }

    func updateNSView(_ containerView: BrowserContainerView, context: Context) {
        print("[BrowserCanvas] ========== updateNSView START ==========")
        print("[BrowserCanvas] pageId: \(pageId), url: \(url.absoluteString)")

        // Ensure we have a valid tab
        guard let tab = browserState.tabManager.tab(for: parentTabId) else {
            print("[BrowserCanvas] Tab \(parentTabId) not found in state")
            return
        }

        print(
            "[BrowserCanvas] Tab has \(tab.pages.count) pages, activePageIndex: \(tab.activePageIndex)"
        )
        for (idx, page) in tab.pages.enumerated() {
            print(
                "[BrowserCanvas]   Page[\(idx)]: browserId=\(page.browserId), isActive=\(idx == tab.activePageIndex)"
            )
        }

        // Get or create the persistent browser view from BrowserManager
        // Use the explicit url parameter to avoid triggering on other property changes
        let cefView = BrowserManager.shared.getBrowser(
            for: pageId,
            url: url,
            delegate: context.coordinator,
            parentTabId: parentTabId
        )

        print(
            "[BrowserCanvas] Got browser for pageId \(pageId), currentURLString: \(cefView.currentURLString)"
        )

        // === REPARENTING LOGIC ===
        // Check if CEF view is already a child of this container
        let needsReparenting = cefView.superview !== containerView
        print(
            "[BrowserCanvas] DEBUG: needsReparenting=\(needsReparenting), superview=\(cefView.superview != nil)"
        )

        if needsReparenting {
            print("[BrowserCanvas] Reparenting CEF view for page \(pageId)")

            // Detach from old parent (if any)
            cefView.removeFromSuperview()

            // Attach to new container
            containerView.addSubview(cefView)

            // Set up Auto Layout constraints to fill container
            cefView.translatesAutoresizingMaskIntoConstraints = false

            // CRITICAL FIX: Deactivate old constraints before adding new ones
            NSLayoutConstraint.deactivate(cefView.constraints)

            NSLayoutConstraint.activate([
                cefView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                cefView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                cefView.topAnchor.constraint(equalTo: containerView.topAnchor),
                cefView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])

            // CRITICAL FIX: Remove layoutSubtreeIfNeeded() - it triggers updateNSView recursively

            // Notify CEF about the new size
            cefView.notifyResize()

            print("[BrowserCanvas] Reparenting complete for page \(pageId)")
        }

        // Update coordinator's current page ID and parent tab ID
        context.coordinator.currentPageId = pageId
        context.coordinator.currentParentTabId = parentTabId

        // Enable/disable stack gestures based on stack mode
        if tab.stackModeEnabled {
            // TODO[SSW] fix horizontal-stack-scroll and enableStackGestures()
            // containerView.enableStackGestures()
            containerView.disableStackGestures()
        } else {
            containerView.disableStackGestures()
        }

        // URL Loading Logic (mirrors WKWebView prototype pattern)
        // In stack mode: Only load URL ONCE when browser is first created (like WKWebView's `if nsView.url == nil`)
        // This prevents the bidirectional sync race condition entirely.
        print(
            "[BrowserCanvas] URL sync check: page.url=\(url.absoluteString), browser.currentURLString=\(cefView.currentURLString)"
        )

        if tab.stackModeEnabled {
            // STACK MODE: Only load if browser hasn't loaded anything yet
            // This is the key insight from the WKWebView prototype - each page's browser
            // loads its URL once and then CEF handles all internal navigation.
            // We never force-navigate based on Page.url mismatches.
            if cefView.currentURLString.isEmpty || cefView.currentURLString == "about:blank" {
                print(
                    "[BrowserCanvas] Stack mode: Initial URL load for new page -> \(url.absoluteString)"
                )
                cefView.loadURL(url)
            } else {
                print(
                    "[BrowserCanvas] ✓ Stack mode: Browser already loaded, not re-navigating (current: \(cefView.currentURLString))"
                )
            }
        } else {
            // NON-STACK MODE: Normal behavior - sync URL changes from address bar
            if url.absoluteString != cefView.currentURLString {
                print(
                    "[BrowserCanvas] Non-stack mode: URL mismatch - navigating browser to \(url.absoluteString)"
                )
                cefView.loadURL(url)
            } else {
                print("[BrowserCanvas] ✓ URLs match, no navigation needed")
            }
        }

        print("[BrowserCanvas] ========== updateNSView END ==========\n")
    }

    static func dismantleNSView(_ containerView: BrowserContainerView, coordinator: Coordinator) {
        // CRITICAL: Do NOT destroy the browser here!
        // Just remove CEF view from container - BrowserManager keeps it alive

        print("[BrowserCanvas] Dismantling viewport (browser preserved)")

        // Clean up subscriptions
        coordinator.cancellables.removeAll()

        // Note: We intentionally do NOT remove subviews or destroy browsers here
        // The CEF views remain in BrowserManager's dictionary and will be reparented
        // when the tab is switched back to, or destroyed when the tab is closed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(browserState: browserState, pageId: pageId, parentTabId: parentTabId)
    }

    // MARK: - Coordinator

    /// Coordinator handles CEF callbacks and updates SwiftUI state
    /// Implements CEFBrowserDelegate for C++ callback bridge
    @MainActor
    class Coordinator: NSObject, CEFBrowserDelegate {
        var browserState: BrowserState
        var currentPageId: UUID
        var currentParentTabId: UUID
        var cancellables = Set<AnyCancellable>()

        // Gesture tracking state
        private var gestureStartTranslation: CGFloat = 0
        private var isGestureActive: Bool = false

        init(browserState: BrowserState, pageId: UUID, parentTabId: UUID) {
            self.browserState = browserState
            self.currentPageId = pageId
            self.currentParentTabId = parentTabId
        }

        /// Handle horizontal pan gestures for page stack navigation
        func handleStackGesture(
            state: NSGestureRecognizer.State, translation: CGFloat, velocity: CGFloat
        ) {
            guard let tab = browserState.tabManager.tab(for: currentParentTabId),
                tab.stackModeEnabled
            else {
                return
            }

            switch state {
            case .began:
                isGestureActive = true
                gestureStartTranslation = translation
                print("[Coordinator] Stack gesture began")

            case .changed:
                guard isGestureActive else { return }

                // Post notification with gesture delta for StackedCanvasView to handle
                NotificationCenter.default.post(
                    name: .stackGestureChanged,
                    object: nil,
                    userInfo: [
                        "tabId": currentParentTabId,
                        "translation": translation,
                        "velocity": velocity,
                    ]
                )

            case .ended, .cancelled, .failed:
                guard isGestureActive else { return }
                isGestureActive = false

                // Post notification with final gesture state
                NotificationCenter.default.post(
                    name: .stackGestureEnded,
                    object: nil,
                    userInfo: [
                        "tabId": currentParentTabId,
                        "translation": translation,
                        "velocity": velocity,
                    ]
                )

                print(
                    "[Coordinator] Stack gesture ended: translation=\(translation), velocity=\(velocity)"
                )

            default:
                break
            }
        }

        /// Subscribe to navigation notifications
        func subscribeToNotifications() {
            // Navigate to URL - use BrowserManager
            NotificationCenter.default.publisher(for: .navigateToURL)
                .compactMap { $0.userInfo?["url"] as? URL }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] url in
                    guard let self = self else { return }
                    BrowserManager.shared.navigate(pageId: self.currentPageId, to: url)
                }
                .store(in: &cancellables)

            // Reload page
            NotificationCenter.default.publisher(for: .reloadPage)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    BrowserManager.shared.reload(pageId: self.currentPageId)
                }
                .store(in: &cancellables)

            // Stop loading
            NotificationCenter.default.publisher(for: .stopLoading)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    BrowserManager.shared.stopLoading(pageId: self.currentPageId)
                }
                .store(in: &cancellables)

            // Go back
            NotificationCenter.default.publisher(for: .goBack)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    BrowserManager.shared.goBack(pageId: self.currentPageId)
                }
                .store(in: &cancellables)

            // Go forward
            NotificationCenter.default.publisher(for: .goForward)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    BrowserManager.shared.goForward(pageId: self.currentPageId)
                }
                .store(in: &cancellables)

            // Zoom In
            NotificationCenter.default.publisher(for: .zoomIn)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    // Only respond if this tab is active (or one of the active split tabs)
                    guard
                        self.browserState.activeTab?.id == self.currentParentTabId
                            || self.browserState.splitTabIds.contains(self.currentParentTabId)
                    else { return }

                    let currentZoom = BrowserManager.shared.getZoomLevel(pageId: self.currentPageId)
                    BrowserManager.shared.setZoomLevel(
                        pageId: self.currentPageId, level: currentZoom + 0.5)
                }
                .store(in: &cancellables)

            // Zoom Out
            NotificationCenter.default.publisher(for: .zoomOut)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    guard
                        self.browserState.activeTab?.id == self.currentParentTabId
                            || self.browserState.splitTabIds.contains(self.currentParentTabId)
                    else { return }

                    let currentZoom = BrowserManager.shared.getZoomLevel(pageId: self.currentPageId)
                    BrowserManager.shared.setZoomLevel(
                        pageId: self.currentPageId, level: currentZoom - 0.5)
                }
                .store(in: &cancellables)

            // Reset Zoom
            NotificationCenter.default.publisher(for: .resetZoom)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self = self else { return }
                    guard
                        self.browserState.activeTab?.id == self.currentParentTabId
                            || self.browserState.splitTabIds.contains(self.currentParentTabId)
                    else { return }

                    BrowserManager.shared.setZoomLevel(pageId: self.currentPageId, level: 0.0)
                }
                .store(in: &cancellables)
        }

        // MARK: - CEFBrowserDelegate Implementation

        func browserDidChangeLoadingState(
            isLoading: Bool, canGoBack: Bool, canGoForward: Bool, url: URL?
        ) {
            print("[Coordinator] ========== browserDidChangeLoadingState ==========")
            print(
                "[Coordinator] Loading state: isLoading=\(isLoading), canGoBack=\(canGoBack), canGoForward=\(canGoForward), url=\(url?.absoluteString ?? "nil")"
            )
            print("[Coordinator] currentPageId: \(currentPageId)")

            // Update loading progress for stack mode pages
            if var tab = browserState.tabManager.tab(for: currentParentTabId), tab.stackModeEnabled
            {
                // Find the page that matches this browser's pageId
                if let pageIndex = tab.pages.firstIndex(where: { $0.browserId == currentPageId }) {
                    tab.pages[pageIndex].isLoading = isLoading
                    tab.pages[pageIndex].canGoBack = canGoBack
                    tab.pages[pageIndex].canGoForward = canGoForward

                    // STACK MODE: Do NOT update Page.url from CEF callbacks!
                    // This mirrors the WKWebView prototype - page.url is only set at creation.
                    // The browser's currentURLString is the source of truth.
                    print(
                        "[Coordinator] ✓ Stack mode: NOT updating Page.url (CEF browser is source of truth)"
                    )

                    // Update address bar if this is the active page
                    if pageIndex == tab.activePageIndex, let url = url {
                        browserState.addressBarText = url.absoluteString
                    }

                    // Get estimated progress from CEF
                    if let browserView = BrowserManager.shared.existingBrowser(for: currentPageId),
                        let handle = browserView.cefBrowserHandle
                    {
                        let progress = cef_get_loading_progress(handle)
                        tab.pages[pageIndex].loadingProgress = progress
                    }

                    // Update lifecycle state when loading completes
                    if !isLoading {
                        tab.pages[pageIndex].lifecycleState = .alive
                        tab.pages[pageIndex].loadingProgress = 1.0
                    }

                    // Update tab in manager
                    browserState.tabManager.replaceTab(id: currentParentTabId, with: tab)
                } else {
                    print("[Coordinator] ⚠️ Could not find page with browserId \(currentPageId)")
                }
            } else {
                // NON-STACK MODE: Normal behavior - update the active tab
                browserState.updateActiveTab(
                    url: url, isLoading: isLoading, canGoBack: canGoBack, canGoForward: canGoForward
                )
            }

            // Dismiss the black loading overlay on first successful page load
            BrowserManager.shared.existingBrowser(for: currentPageId)?.setLoadingState(isLoading)

            print("[Coordinator] =============================================\n")
        }

        func browserDidChangeTitle(_ title: String) {
            print("[Coordinator] Title changed: \(title)")

            // Update page title in stack mode, or pane title in normal mode
            if var tab = browserState.tabManager.tab(for: currentParentTabId), tab.stackModeEnabled
            {
                if let pageIndex = tab.pages.firstIndex(where: { $0.browserId == currentPageId }) {
                    tab.pages[pageIndex].title = title
                    browserState.tabManager.replaceTab(id: currentParentTabId, with: tab)
                }
            } else {
                browserState.updateActiveTab(title: title)
            }
        }

        func browserDidChangeURL(_ url: URL) {
            print("[Coordinator] ========== browserDidChangeURL ==========")
            print("[Coordinator] URL changed: \(url.absoluteString)")
            print(
                "[Coordinator] currentPageId: \(currentPageId), currentParentTabId: \(currentParentTabId)"
            )

            // Check if we're in stack mode
            if let tab = browserState.tabManager.tab(for: currentParentTabId), tab.stackModeEnabled
            {
                // STACK MODE: Do NOT update Page.url from CEF callbacks!
                // This mirrors the WKWebView prototype approach where page.url is only set at creation.
                // The browser's currentURLString is the source of truth for what's loaded.
                // This prevents the race condition where CEF callbacks update the model,
                // then updateNSView sees a mismatch and re-navigates.
                print(
                    "[Coordinator] ✓ Stack mode: NOT updating Page.url (CEF browser is source of truth)"
                )

                // Only update address bar if this is the active page
                if let pageIndex = tab.pages.firstIndex(where: { $0.browserId == currentPageId }),
                    pageIndex == tab.activePageIndex
                {
                    browserState.addressBarText = url.absoluteString
                    print("[Coordinator] ✓ Updated address bar for active page")
                }
            } else {
                // NON-STACK MODE: Normal behavior - update the tab's URL
                print("[Coordinator] Updating active tab URL (non-stack mode)")
                browserState.updateActiveTab(url: url)
            }
            print("[Coordinator] ==========================================\n")
        }

        func browserDidChangeFaviconURL(_ faviconURL: URL?) {
            print("[Coordinator] Favicon URL changed: \(faviconURL?.absoluteString ?? "nil")")

            guard let activeTab = browserState.activeTab else { return }

            // Capture values BEFORE async call to prevent race conditions
            let capturedTabId = activeTab.id
            let capturedPaneId = activeTab.activePaneId
            let capturedPageId = currentPageId
            let capturedPageURL = activeTab.url
            let isStackMode = activeTab.stackModeEnabled

            Task { @MainActor in
                let image = await FaviconLoader.shared.downloadFavicon(
                    from: faviconURL,
                    pageURL: capturedPageURL
                )

                // Verify the tab still exists before updating
                guard var tab = self.browserState.tabManager.tab(for: capturedTabId) else {
                    print("[Coordinator] Tab \(capturedTabId) no longer exists, discarding favicon")
                    return
                }

                if isStackMode {
                    // Update page icon in stack mode
                    if let pageIndex = tab.pages.firstIndex(where: {
                        $0.browserId == capturedPageId
                    }) {
                        tab.pages[pageIndex].icon = image
                        tab.pages[pageIndex].favicon = image?.tiffRepresentation
                        self.browserState.tabManager.replaceTab(id: capturedTabId, with: tab)
                        print("[Coordinator] Favicon updated for page in tab \(capturedTabId)")
                    }
                } else {
                    // Update pane icon in normal mode
                    self.browserState.updatePaneIcon(paneId: capturedPaneId, icon: image)
                    print("[Coordinator] Favicon updated for tab \(capturedTabId)")
                }
            }
        }

        func browserDidCapturePreview(_ preview: NSImage) {
            guard let activeTab = browserState.activeTab else { return }
            let tabId = activeTab.id
            print("[Coordinator] Preview captured for tab \(tabId)")
            browserState.updateTabPreview(tabId: tabId, preview: preview)
        }

        func browserDidRequestOpenLinkAsChildTab(_ url: URL, parentTabId: UUID) {
            print("[Coordinator] Opening link as child tab: \(url), parentTabId: \(parentTabId)")

            // CRITICAL: Use the parentTabId provided by the callback bridge
            // This is the tab ID that OWNS the browser (set at browser creation),
            // ensuring correct parent even if the coordinator's currentTabId changed
            _ = browserState.tabManager.createChildTab(
                url: url,
                title: "New Tab",
                parentId: parentTabId
            )

            print("[Coordinator] Created child tab for parent \(parentTabId)")
        }

        func browserDidRequestMediaPermission(
            requestingOrigin: String, requestedPermissions: Int, handle: CefBrowserHandle
        ) {
            print(
                "[Coordinator] Media permission requested: origin=\(requestingOrigin), permissions=0x\(String(requestedPermissions, radix: 16))"
            )

            // Global Settings Check
            let settings = browserState.settingsManager
            let audioRequested = (requestedPermissions & 1) != 0
            let videoRequested = (requestedPermissions & 2) != 0

            var allowAudio = false
            var allowVideo = false
            var askAudio = false
            var askVideo = false

            // Check Microphone settings
            if audioRequested {
                switch settings.microphonePermission {
                case .allow: allowAudio = true
                case .block: allowAudio = false
                case .ask: askAudio = true
                }
            }

            // Check Camera settings
            if videoRequested {
                switch settings.cameraPermission {
                case .allow: allowVideo = true
                case .block: allowVideo = false
                case .ask: askVideo = true
                }
            }

            // If any requested part is "Ask", we must show the dialog (unless all are Blocked effectively?)
            // If we Ask, the dialog handles the final decision.
            // If we don't ask, we construct the allow mask.

            let needToAsk = (audioRequested && askAudio) || (videoRequested && askVideo)

            if !needToAsk {
                // Auto-respond based on settings
                var allowedMask = 0
                if audioRequested && allowAudio { allowedMask |= 1 }
                if videoRequested && allowVideo { allowedMask |= 2 }

                print(
                    "[Coordinator] Auto-responding based on settings: 0x\(String(allowedMask, radix: 16))"
                )

                // Use CEFBridge to ensure C++ compat (though direct call works if imported)
                // Using helper function from BrowserView logic - which calls cef_respond_to_media_permission direct
                cef_respond_to_media_permission(handle, Int32(allowedMask))
                return
            }

            // Show permission dialog and handle user response
            MediaPermissionDialog.requestPermission(
                origin: requestingOrigin,
                requestedPermissions: requestedPermissions
            ) { allowedPermissions in
                // Respond to CEF with user's decision
                cef_respond_to_media_permission(handle, Int32(allowedPermissions))
                print(
                    "[Coordinator] Responded to media permission request with: 0x\(String(allowedPermissions, radix: 16))"
                )
            }
        }

        func browserDidRequestLinkNavigation(_ url: URL) -> Bool {
            print(
                "[Coordinator] ========== browserDidRequestLinkNavigation (Registry Mode) =========="
            )
            print("[Coordinator] 🔗 Link clicked: \(url.absoluteString)")
            print(
                "[Coordinator] currentPageId: \(currentPageId), currentParentTabId: \(currentParentTabId)"
            )

            // This method is called asynchronously from C callback only when stack mode is active.
            // Navigation is ALREADY cancelled by the C callback (returning 0).

            print("[Coordinator] 🔗 Stack Mode Navigation Handler Triggered")

            let startTime = Date()

            // Re-fetch tab to ensure we have the latest state
            guard var tab = self.browserState.tabManager.tab(for: self.currentParentTabId)
            else {
                print("[Coordinator] ⚠️ Tab not found, cannot open new page")
                return false
            }

            // Check max pages
            if tab.pages.count >= 5 {
                print("[Coordinator] 🛑 Max pages reached (\(tab.pages.count)). Ignoring link.")
                return false
            }

            // Create new page in stack
            let newPage = Page(
                url: url,
                title: "Loading...",
                isLoading: true
            )
            print("[Coordinator] ➕ Creating new page: \(newPage.browserId)")

            tab.pages.append(newPage)

            let (trimmedPages, removedIndex) = PageLifecycleManager.enforcePageLimit(tab.pages)

            if let removedIndex = removedIndex, tab.pages.indices.contains(removedIndex) {
                let removedPage = tab.pages[removedIndex]
                BrowserManager.shared.closeBrowser(for: removedPage.browserId)
            }

            tab.pages = trimmedPages

            if let removedIndex = removedIndex {
                if removedIndex < tab.activePageIndex {
                    tab.activePageIndex -= 1
                } else if removedIndex == tab.activePageIndex {
                    tab.activePageIndex = max(0, tab.pages.count - 1)
                }
            }

            tab.activePageIndex = tab.pages.count - 1

            self.browserState.tabManager.replaceTab(id: self.currentParentTabId, with: tab)
            print(
                "[Coordinator] ✅ Page added (Elapsed: \(String(format: "%.3f", Date().timeIntervalSince(startTime)))s)"
            )

            self.browserState.addressBarText = url.absoluteString

            print("[Coordinator] ✨ Navigation logic finished")
            print("[Coordinator] ======================================================\n")

            return false
        }
    }
}

// =============================================================================
// MARK: - Browser Container View (Viewport)
// =============================================================================

/// Simple NSView that acts as a container/viewport for reparented CEF browser views
/// Supports gesture recognition for page stack navigation
class BrowserContainerView: NSView {

    /// Callback for horizontal pan gestures (used for page stack navigation)
    var onHorizontalPan: ((NSGestureRecognizer.State, CGFloat, CGFloat) -> Void)?

    /// Pan gesture recognizer for trackpad swipes
    private var panGestureRecognizer: NSPanGestureRecognizer?

    /// Monitor for local scroll events (trackpad swipes)
    private var scrollEventMonitor: Any?

    /// Accumulated horizontal scroll delta for gesture synthesis
    private var accumulatedScrollDeltaX: CGFloat = 0

    /// Threshold to start a "gesture" from scroll events
    private let scrollGestureThreshold: CGFloat = 10.0

    /// Whether we are currently tracking a synthesized scroll gesture
    private var isTrackingScrollGesture: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    /// Enable gesture recognition for page stack navigation
    /// Call this when stack mode is enabled for the tab
    func enableStackGestures() {
        // 1. Enable Pan Gesture (standard API, creates a recognizer)
        if panGestureRecognizer == nil {
            let panGesture = NSPanGestureRecognizer(
                target: self, action: #selector(handlePanGesture(_:)))
            panGesture.delegate = self
            addGestureRecognizer(panGesture)
            panGestureRecognizer = panGesture
        }

        // 2. Enable Scroll/Swipe Monitor (NSEvent local monitor)
        // This intercepts scroll events BEFORE they reach CEF's view.
        if scrollEventMonitor == nil {
            scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                return self?.handleScrollEvent(event)
            }
        }

        print("[BrowserContainerView] Stack gestures enabled (Pan + ScrollMonitor)")
    }

    /// Disable gesture recognition (when stack mode is disabled)
    func disableStackGestures() {
        // 1. Remove Pan Gesture
        if let gesture = panGestureRecognizer {
            removeGestureRecognizer(gesture)
            panGestureRecognizer = nil
        }

        // 2. Remove Scroll Monitor
        if let monitor = scrollEventMonitor {
            NSEvent.removeMonitor(monitor)
            scrollEventMonitor = nil
        }

        // Reset state
        isTrackingScrollGesture = false
        accumulatedScrollDeltaX = 0

        print("[BrowserContainerView] Stack gestures disabled")
    }

    /// Handle scroll events intercepted from the window
    /// Returns the event to pass it through to CEF while tracking for stack navigation
    private func handleScrollEvent(_ event: NSEvent) -> NSEvent? {
        // Determine dominant direction
        let isHorizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)

        // Track horizontal scrolls for potential stack navigation
        // We observe the events but ALWAYS pass them through to CEF
        if isHorizontal {

            switch event.phase {
            case .began:
                accumulatedScrollDeltaX = 0
                isTrackingScrollGesture = true
                onHorizontalPan?(.began, 0, 0)

            case .changed:
                if isTrackingScrollGesture {
                    accumulatedScrollDeltaX += event.scrollingDeltaX
                    onHorizontalPan?(.changed, accumulatedScrollDeltaX, 0)
                }

            case .ended, .cancelled:
                if isTrackingScrollGesture {
                    onHorizontalPan?(.ended, accumulatedScrollDeltaX, 0)
                    isTrackingScrollGesture = false
                    accumulatedScrollDeltaX = 0
                }

            default:
                break
            }
        }

        // ALWAYS return event - let CEF handle webpage scrolling
        // The StackedCanvasView will decide if the accumulated delta is large enough
        // to trigger page navigation
        return event
    }

    @objc private func handlePanGesture(_ gesture: NSPanGestureRecognizer) {
        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)

        // Forward to SwiftUI via callback
        onHorizontalPan?(gesture.state, translation.x, velocity.x)
    }

    override func layout() {
        super.layout()

        // Notify CEF subviews about resize
        for subview in subviews {
            if let cefView = subview as? CEFContainerView {
                cefView.notifyResize()
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            // Force layout when attached to window
            layoutSubtreeIfNeeded()

            // Notify CEF subviews
            for subview in subviews {
                if let cefView = subview as? CEFContainerView {
                    cefView.notifyResize()
                }
            }
        }
    }
}

// MARK: - NSGestureRecognizerDelegate

extension BrowserContainerView: NSGestureRecognizerDelegate {

    /// Allow pan gesture to work simultaneously with CEF's internal gestures
    /// This enables horizontal swipes for page navigation while allowing vertical scrolling
    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        // Allow simultaneous recognition with CEF's scroll gestures
        return true
    }

    /// Determine if gesture should begin based on direction
    func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
        guard let panGesture = gestureRecognizer as? NSPanGestureRecognizer else {
            return true
        }

        let translation = panGesture.translation(in: self)
        let velocity = panGesture.velocity(in: self)

        // Only recognize primarily horizontal gestures
        // This prevents interfering with vertical scrolling in CEF
        let isHorizontal =
            abs(translation.x) > abs(translation.y) || abs(velocity.x) > abs(velocity.y)

        return isHorizontal
    }
}

// =============================================================================
// MARK: - CEF Container View (NSView)
// =============================================================================

/// Native NSView container that hosts the CEF browser rendering surface
///
/// Architecture:
/// - CEF creates its own NSView (or CALayer) for rendering
/// - We provide this container as the parent view
/// - CefWindowInfo.SetAsChild embeds CEF's view as a child
/// - Layout changes trigger WasResized() for content reflow
class CEFContainerView: NSView {

    /// Coordinator for SwiftUI state updates (supports both BrowserCanvas and legacy BrowserView)
    weak var coordinator: (any CEFBrowserDelegate)?

    /// Browser state reference
    weak var browserState: BrowserState?

    /// The page ID that owns this browser view
    /// CRITICAL: This is set once at creation and identifies which page this browser belongs to
    private(set) var pageId: UUID?

    /// The parent tab ID for opening child tabs
    /// Used for correct parent identification when opening new tabs from links
    private(set) var parentTabId: UUID?

    /// Current URL string (for change detection)
    private(set) var currentURLString: String = ""

    /// CEF browser handle (opaque pointer from cef_shim)
    /// Exposed as private(set) for BrowserManager callback registration
    private(set) var cefBrowserHandle: CefBrowserHandle?

    /// Whether the browser has been created
    private var browserCreated: Bool = false

    /// Pending URL to load after browser is created
    private var pendingURL: URL?

    /// Message loop timer for CEF integration with Cocoa run loop
    /// Using nonisolated(unsafe) to allow access in deinit
    nonisolated(unsafe) private var messageLoopTimer: Timer?

    /// Display link for smooth message loop integration
    nonisolated(unsafe) private var displayLink: CVDisplayLink?

    /// Whether we're currently in a resize operation
    private var isResizing: Bool = false

    /// Black overlay shown until the first page load completes
    private var loadingOverlay: NSView?

    /// Spinner shown on top of the black loading overlay
    private var loadingSpinner: NSProgressIndicator?

    /// Whether the first page load has finished (overlay is shown only until then)
    private var hasCompletedFirstLoad: Bool = false

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        // Configure view for CEF hosting
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        // Enable layer-backed view for better compositing with CEF
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        // Start CEF message loop integration
        startMessageLoop()

        // Register for frame change notifications (for resize handling)
        postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(frameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: self
        )

        setupLoadingOverlay()

        print("[CEFView] Container initialized with layer-backed rendering")
    }

    private func setupLoadingOverlay() {
        let overlay = NSView(frame: bounds)
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.cgColor
        overlay.autoresizingMask = [.width, .height]

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .large
        spinner.appearance = NSAppearance(named: .darkAqua)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(spinner)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
        ])

        spinner.startAnimation(nil)
        addSubview(overlay)

        loadingOverlay = overlay
        loadingSpinner = spinner
    }

    deinit {
        // Clean up timer - invalidate on the main thread
        messageLoopTimer?.invalidate()
        messageLoopTimer = nil

        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
        }
        displayLink = nil

        NotificationCenter.default.removeObserver(self)
        print("[CEFView] Container deallocated")
    }

    // MARK: - Public API for BrowserManager

    /// Notify CEF about a resize (called after reparenting or container resize)
    func notifyResize() {
        guard let handle = cefBrowserHandle else { return }
        let size = bounds.size
        guard size.width > 0 && size.height > 0 else { return }

        print("[CEFView] notifyResize: \(Int(size.width))x\(Int(size.height))")
        cef_resize_browser(handle, Int32(size.width), Int32(size.height))
    }

    /// Update the delegate for callback routing (used during reparenting)
    /// NOTE: This preserves the original pageId - the browser always belongs to the same page
    func updateDelegate(_ delegate: any CEFBrowserDelegate) {
        self.coordinator = delegate

        // Update delegate but preserve the original pageId
        if let handle = cefBrowserHandle {
            CEFCallbackBridge.updateDelegate(for: handle, delegate: delegate)
            print("[CEFView] Updated delegate (pageId preserved: \(pageId?.uuidString ?? "nil"))")
        }
    }

    /// Set the page ID that owns this browser (should only be called once at creation)
    func setPageId(_ id: UUID) {
        guard pageId == nil else {
            print(
                "[CEFView] WARNING: Attempted to change pageId from \(pageId!) to \(id) - ignoring")
            return
        }
        pageId = id
        print("[CEFView] Page ID set to: \(id)")
    }

    /// Set the parent tab ID for child tab creation (should only be called once at creation)
    func setParentTabId(_ id: UUID) {
        guard parentTabId == nil else {
            print(
                "[CEFView] WARNING: Attempted to change parentTabId from \(parentTabId!) to \(id) - ignoring"
            )
            return
        }
        parentTabId = id
        print("[CEFView] Parent Tab ID set to: \(id)")
    }

    /// Show or hide the black loading overlay.
    /// Call with `isLoading: false` once the first page load completes to fade the overlay out.
    func setLoadingState(_ isLoading: Bool) {
        guard !hasCompletedFirstLoad else { return }

        if !isLoading {
            hasCompletedFirstLoad = true
            guard let overlay = loadingOverlay else { return }
            loadingSpinner?.stopAnimation(nil)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                overlay.animator().alphaValue = 0
            }, completionHandler: {
                overlay.removeFromSuperview()
                self.loadingOverlay = nil
                self.loadingSpinner = nil
            })
        }
    }

    /// Notify CEF that a split resize operation is starting.
    /// Called from SplitCanvasViewController when split divider drag begins.
    /// This helps CEF optimize rendering during the resize operation.
    func notifySplitResizeStarted() {
        guard let handle = cefBrowserHandle else { return }
        cef_notify_move_or_resize_started(handle)
    }

    /// Configure autoresizing for CEF's internal browser NSView
    ///
    /// CRITICAL FIX: CEF creates its own NSView as a child of our container.
    /// By default, this child view may not have proper autoresizingMask set,
    /// causing gaps during horizontal (height) resizes while vertical (width) resizes work.
    ///
    /// This method ensures the CEF browser view resizes with both width AND height.
    private func configureCEFBrowserViewAutoresizing(handle: CefBrowserHandle) {
        // Get the CEF browser's internal NSView
        guard let browserViewPtr = cef_get_browser_view(handle) else {
            print("[CEFView] Cannot configure autoresizing - no browser view")
            return
        }

        // The pointer is an Unmanaged NSView
        let browserView = Unmanaged<NSView>.fromOpaque(browserViewPtr).takeUnretainedValue()

        // Configure autoresizing to follow parent size changes in BOTH dimensions
        // This is critical for horizontal splits (height changes)
        browserView.autoresizingMask = [.width, .height]
        browserView.translatesAutoresizingMaskIntoConstraints = true

        // Ensure the browser view fills the container
        browserView.frame = self.bounds

        print(
            "[CEFView] Configured CEF browser view autoresizing: width+height, frame: \(browserView.frame)"
        )
    }

    // MARK: - CEF Message Loop Integration

    /// Start the CEF message loop timer
    /// CEF requires CefDoMessageLoopWork() to be called periodically
    /// when using external_message_pump = true
    private func startMessageLoop() {
        // Use a timer that fires at ~60Hz for smooth UI updates
        // This integrates CEF's message loop with the Cocoa run loop
        messageLoopTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            // Call CEF message work on each timer fire
            // This is safe because Timer fires on the main run loop
            cef_do_message_work()
        }

        // Add timer to common run loop modes so it fires during tracking
        if let timer = messageLoopTimer {
            RunLoop.current.add(timer, forMode: .common)
        }

        print("[CEFView] Message loop timer started (60Hz)")
    }

    /// Stop the CEF message loop timer
    private func stopMessageLoop() {
        messageLoopTimer?.invalidate()
        messageLoopTimer = nil

        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }

        print("[CEFView] Message loop timer stopped")
    }

    /// Perform CEF message loop work
    /// This processes pending CEF events and repaints
    private func performMessageLoopWork() {
        // Only do work if CEF is initialized
        _ = cef_do_message_work()
    }

    // MARK: - Browser Creation

    /// Create the CEF browser instance
    /// Must be called after the view has a valid window and frame
    private func createBrowserIfNeeded(url: URL) {
        guard !browserCreated else {
            // Browser already created, just navigate
            navigateToURL(url)
            return
        }

        // Ensure we have a valid frame
        let size = bounds.size
        guard size.width > 0 && size.height > 0 else {
            pendingURL = url
            print("[CEFView] View not sized yet, deferring browser creation")
            return
        }

        // Ensure we're attached to a window
        guard window != nil else {
            pendingURL = url
            print("[CEFView] Not attached to window yet, deferring browser creation")
            return
        }

        print("[CEFView] Creating CEF browser - size: \(Int(size.width))x\(Int(size.height))")

        // Check if stack-mode is enabled for this page's parent tab to disable swipe navigation
        let disableSwipeNav: Bool
        if let unwrappedParentTabId = parentTabId,
            let coordinator = coordinator as? BrowserCanvas.Coordinator
        {
            coordinator.browserState.tabManager.tabs.enumerated().forEach { index, tab in
                print("[CEFView]   [\(index)] id=\(tab.id), stackMode=\(tab.stackModeEnabled)")
            }
            let tabTemp = coordinator.browserState.tabManager.tab(for: unwrappedParentTabId)
            print("[CEFView] Found tab: \(tabTemp != nil ? "YES" : "NO")")
            disableSwipeNav = tabTemp?.stackModeEnabled ?? false
        } else {
            disableSwipeNav = false
        }
        print(
            "[CEFView] Stack-mode enabled: \(disableSwipeNav), swipe navigation will be \(disableSwipeNav ? "disabled" : "enabled")"
        )

        // Create browser with this view as the parent container
        // CEF will create its own child NSView for rendering
        // IPC FLOW: Swift -> cef_create_browser -> CefWindowInfo.SetAsChild -> CEF renders into child view
        let handle = url.absoluteString.withCString { urlCString in
            cef_create_browser(
                Unmanaged.passUnretained(self).toOpaque(),
                urlCString,
                Int32(size.width),
                Int32(size.height),
                disableSwipeNav ? 1 : 0
            )
        }

        if let handle = handle {
            cefBrowserHandle = handle
            browserCreated = true
            currentURLString = url.absoluteString

            print("[CEFView] CEF browser created successfully")

            // CRITICAL: Configure CEF's internal NSView for proper autoresizing
            // CEF creates its own NSView as a child - we need to set its autoresizing mask
            // This fixes the resize gap issue, especially for horizontal splits
            configureCEFBrowserViewAutoresizing(handle: handle)

            // CRITICAL: Register callbacks for CEF -> Swift communication
            // This enables title changes and load state updates to flow to SwiftUI
            // Pass parentTabId for correct parent identification when opening child tabs
            if let coordinator = coordinator {
                if let unwrappedParentTabId = parentTabId {
                    CEFCallbackBridge.registerCallbacks(
                        for: handle, delegate: coordinator, tabId: unwrappedParentTabId)
                    print(
                        "[CEFView] CEF callbacks registered with coordinator, parentTabId: \(unwrappedParentTabId)"
                    )
                } else {
                    // Fallback: register without parentTabId (child tab feature won't work correctly)
                    print(
                        "[CEFView] WARNING: No parentTabId set - child tab parent identification may fail"
                    )
                    // Create a placeholder UUID - this shouldn't happen in normal flow
                    let placeholderTabId = UUID()
                    CEFCallbackBridge.registerCallbacks(
                        for: handle, delegate: coordinator, tabId: placeholderTabId)
                }

                // CRITICAL: Set stack mode in registry to control navigation policy
                // This allows the C callback to cancel navigation synchronously matches disableSwipeNav
                CEFCallbackBridge.setStackMode(disableSwipeNav, for: handle)
                print("[CEFView] Stack mode set in registry: \(disableSwipeNav)")
            }

            // Notify coordinator of load start
            Task { @MainActor [weak self] in
                self?.coordinator?.onLoadStart(url: url)
            }

            // Update navigation state after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.updateNavigationState()
            }
        } else {
            print("[CEFView] Failed to create CEF browser - showing fallback UI")
            addPlaceholderContent()
        }
    }

    /// Navigate to a URL in the existing browser
    private func navigateToURL(_ url: URL) {
        guard let handle = cefBrowserHandle else { return }

        print("[CEFView] ========== navigateToURL ==========")
        print("[CEFView] 🌐 Navigating browser to: \(url.absoluteString)")
        print("[CEFView] pageId: \(pageId?.uuidString ?? "nil")")
        print("[CEFView] Previous currentURLString: \(currentURLString)")

        currentURLString = url.absoluteString
        print("[CEFView] Updated currentURLString to: \(currentURLString)")

        url.absoluteString.withCString { urlCString in
            cef_navigate_to_url(handle, urlCString)
        }

        print("[CEFView] ✓ CEF navigation initiated")
        print("[CEFView] =====================================\n")

        Task { @MainActor [weak self] in
            self?.coordinator?.onLoadStart(url: url)
        }
    }

    /// Update navigation state (back/forward availability)
    private func updateNavigationState() {
        guard let handle = cefBrowserHandle else { return }

        let canGoBack = cef_can_go_back(handle) != 0
        let canGoForward = cef_can_go_forward(handle) != 0

        Task { @MainActor [weak self] in
            self?.coordinator?.onNavigationStateChange(
                canGoBack: canGoBack, canGoForward: canGoForward)
        }
    }

    /// Add placeholder content when CEF fails to initialize
    private func addPlaceholderContent() {
        let container = NSView(frame: bounds)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.autoresizingMask = [.width, .height]

        let label = NSTextField(
            wrappingLabelWithString: """
                🌐 CEF Browser Canvas

                CEF initialization failed or is not available.

                To set up CEF:
                1. Download CEF from https://cef-builds.spotifycdn.com
                2. Place framework in Vendor/cef/Release/
                3. Build libcef_dll_wrapper
                4. Rebuild the project

                See README.md for detailed setup instructions.
                """)
        label.alignment = .center
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isSelectable = false
        label.backgroundColor = .clear
        label.isBordered = false

        container.addSubview(label)
        addSubview(container)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -40),
        ])
    }

    // MARK: - Public Browser Control API

    /// Load a URL in the browser
    func loadURL(_ url: URL) {
        print("[CEFView] loadURL called: \(url.absoluteString)")
        createBrowserIfNeeded(url: url)
    }

    /// Navigate back in history
    func goBack() {
        guard let handle = cefBrowserHandle else { return }
        print("[CEFView] Going back")
        cef_go_back(handle)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.updateNavigationState()
        }
    }

    /// Navigate forward in history
    func goForward() {
        guard let handle = cefBrowserHandle else { return }
        print("[CEFView] Going forward")
        cef_go_forward(handle)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.updateNavigationState()
        }
    }

    /// Reload the current page
    func reload() {
        guard let handle = cefBrowserHandle else { return }
        print("[CEFView] Reloading")
        cef_reload(handle)

        Task { @MainActor [weak self] in
            if let url = URL(string: self?.currentURLString ?? "") {
                self?.coordinator?.onLoadStart(url: url)
            }
        }
    }

    /// Stop loading
    func stopLoading() {
        guard let handle = cefBrowserHandle else { return }
        print("[CEFView] Stopping load")
        cef_stop_loading(handle)

        Task { @MainActor [weak self] in
            self?.browserState?.navigationState.update(isLoading: false)
        }
    }

    /// Set the zoom level for this browser
    func setZoomLevel(_ level: Double) {
        guard let handle = cefBrowserHandle else { return }
        print("[CEFView] Setting zoom level to: \(level)")
        cef_set_zoom_level(handle, level)
    }

    /// Get the current zoom level for this browser
    func getZoomLevel() -> Double {
        guard let handle = cefBrowserHandle else { return 0.0 }
        return cef_get_zoom_level(handle)
    }

    /// Destroy the browser instance
    func destroyBrowser() {
        guard let handle = cefBrowserHandle else { return }

        print("[CEFView] Destroying browser")

        // Unregister callbacks before destroying browser
        CEFCallbackBridge.unregisterCallbacks(for: handle)

        cef_destroy_browser(handle)
        cefBrowserHandle = nil
        browserCreated = false
    }

    /// Capture a snapshot of the current browser view for tab preview
    /// Uses the Cache-on-Exit strategy - called before tab switching
    ///
    /// CRITICAL: CEF uses hardware-accelerated (GPU) rendering which cannot be captured
    /// via standard NSView snapshot APIs. We use multiple fallback strategies:
    /// 1. Try CEF's browser view directly via bitmapImageRepForCachingDisplay
    /// 2. Try the window's snapshot API
    /// 3. Try layer-based rendering as last resort
    ///
    /// - Parameter completion: Called with the snapshot NSImage (or nil on failure)
    func captureSnapshot(completion: @escaping @MainActor (NSImage?) -> Void) {
        guard let handle = cefBrowserHandle else {
            print("[CEFView] No browser handle for snapshot")
            Task { @MainActor in completion(nil) }
            return
        }

        print("[CEFView] Capturing snapshot for tab preview...")

        // Get bounds for aspect ratio calculation
        let viewBounds = bounds
        guard viewBounds.width > 0, viewBounds.height > 0 else {
            print("[CEFView] Invalid view bounds: \(viewBounds)")
            Task { @MainActor in completion(nil) }
            return
        }

        // Calculate thumbnail size maintaining aspect ratio
        let targetWidth: CGFloat = 320.0
        let aspectRatio = viewBounds.height / viewBounds.width
        let thumbnailSize = NSSize(width: targetWidth, height: targetWidth * aspectRatio)

        print(
            "[CEFView] View bounds: \(Int(viewBounds.width))x\(Int(viewBounds.height)), target: \(Int(thumbnailSize.width))x\(Int(thumbnailSize.height))"
        )

        // Strategy 1: Try to get CEF's browser view and snapshot it directly
        if let browserViewPtr = cef_get_browser_view(handle) {
            let cefView = Unmanaged<NSView>.fromOpaque(browserViewPtr).takeUnretainedValue()

            // Check if CEF view has valid bounds
            let cefBounds = cefView.bounds
            if cefBounds.width > 0 && cefBounds.height > 0 {
                print(
                    "[CEFView] Trying CEF view snapshot: \(Int(cefBounds.width))x\(Int(cefBounds.height))"
                )

                // Use the window's cacheImageInRect for hardware-accelerated content
                if let window = cefView.window {
                    // Convert CEF view bounds to window coordinates
                    let windowRect = cefView.convert(cefBounds, to: nil)

                    // Try window's bitmap snapshot (captures composited content)
                    if let cgImage = CGWindowListCreateImage(
                        windowRect,
                        .optionIncludingWindow,
                        CGWindowID(window.windowNumber),
                        [.boundsIgnoreFraming, .nominalResolution]
                    ) {
                        let fullImage = NSImage(cgImage: cgImage, size: cefBounds.size)

                        // Create scaled thumbnail
                        let thumbnail = NSImage(size: thumbnailSize)
                        thumbnail.lockFocus()
                        NSGraphicsContext.current?.imageInterpolation = .high
                        fullImage.draw(
                            in: NSRect(origin: .zero, size: thumbnailSize),
                            from: NSRect(origin: .zero, size: fullImage.size),
                            operation: .copy,
                            fraction: 1.0)
                        thumbnail.unlockFocus()

                        print(
                            "[CEFView] Snapshot captured via CGWindowListCreateImage: \(Int(thumbnailSize.width))x\(Int(thumbnailSize.height))"
                        )
                        Task { @MainActor in completion(thumbnail) }
                        return
                    }
                }

                // Fallback: Try bitmapImageRepForCachingDisplay on CEF view
                if let bitmapRep = cefView.bitmapImageRepForCachingDisplay(in: cefBounds) {
                    cefView.cacheDisplay(in: cefBounds, to: bitmapRep)

                    // Check if we got actual pixels (not just empty/transparent)
                    if let bitmapData = bitmapRep.bitmapData {
                        var hasContent = false
                        let pixelCount = min(1000, bitmapRep.pixelsWide * bitmapRep.pixelsHigh)
                        for i in stride(from: 0, to: pixelCount * 4, by: 4) {
                            // Check alpha channel - if any pixel has content, we're good
                            if bitmapData[i + 3] > 10 {  // Alpha > 10
                                hasContent = true
                                break
                            }
                        }

                        if hasContent {
                            let fullImage = NSImage(size: cefBounds.size)
                            fullImage.addRepresentation(bitmapRep)

                            // Create scaled thumbnail
                            let thumbnail = NSImage(size: thumbnailSize)
                            thumbnail.lockFocus()
                            NSGraphicsContext.current?.imageInterpolation = .high
                            fullImage.draw(
                                in: NSRect(origin: .zero, size: thumbnailSize),
                                from: NSRect(origin: .zero, size: cefBounds.size),
                                operation: .copy,
                                fraction: 1.0)
                            thumbnail.unlockFocus()

                            print(
                                "[CEFView] Snapshot captured via CEF view bitmap: \(Int(thumbnailSize.width))x\(Int(thumbnailSize.height))"
                            )
                            Task { @MainActor in completion(thumbnail) }
                            return
                        } else {
                            print("[CEFView] CEF view bitmap was empty, trying fallback...")
                        }
                    }
                }
            }
        }

        // Strategy 2: Try our container view's layer rendering
        if let layer = layer, layer.contents != nil || layer.sublayers?.isEmpty == false {
            print("[CEFView] Trying layer-based snapshot...")

            let scale = window?.backingScaleFactor ?? 2.0
            let layerSize = NSSize(
                width: viewBounds.width * scale, height: viewBounds.height * scale)

            if let offscreenRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(layerSize.width),
                pixelsHigh: Int(layerSize.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: Int(layerSize.width) * 4,
                bitsPerPixel: 32
            ) {
                if let context = NSGraphicsContext(bitmapImageRep: offscreenRep) {
                    let cgContext = context.cgContext
                    cgContext.scaleBy(x: scale, y: scale)
                    layer.render(in: cgContext)

                    // Check if we got content
                    if let bitmapData = offscreenRep.bitmapData {
                        var hasContent = false
                        let pixelCount = min(
                            1000, offscreenRep.pixelsWide * offscreenRep.pixelsHigh)
                        for i in stride(from: 0, to: pixelCount * 4, by: 4) {
                            if bitmapData[i + 3] > 10 {
                                hasContent = true
                                break
                            }
                        }

                        if hasContent {
                            let fullImage = NSImage(size: viewBounds.size)
                            fullImage.addRepresentation(offscreenRep)

                            let thumbnail = NSImage(size: thumbnailSize)
                            thumbnail.lockFocus()
                            NSGraphicsContext.current?.imageInterpolation = .high
                            fullImage.draw(
                                in: NSRect(origin: .zero, size: thumbnailSize),
                                from: NSRect(origin: .zero, size: viewBounds.size),
                                operation: .copy,
                                fraction: 1.0)
                            thumbnail.unlockFocus()

                            print(
                                "[CEFView] Snapshot captured via layer render: \(Int(thumbnailSize.width))x\(Int(thumbnailSize.height))"
                            )
                            Task { @MainActor in completion(thumbnail) }
                            return
                        }
                    }
                }
            }
        }

        // Strategy 3: Use our own view's bitmapImageRepForCachingDisplay as last resort
        print("[CEFView] Trying container view bitmap as last resort...")
        if let bitmapRep = bitmapImageRepForCachingDisplay(in: viewBounds) {
            cacheDisplay(in: viewBounds, to: bitmapRep)

            let fullImage = NSImage(size: viewBounds.size)
            fullImage.addRepresentation(bitmapRep)

            let thumbnail = NSImage(size: thumbnailSize)
            thumbnail.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            fullImage.draw(
                in: NSRect(origin: .zero, size: thumbnailSize),
                from: NSRect(origin: .zero, size: viewBounds.size),
                operation: .copy,
                fraction: 1.0)
            thumbnail.unlockFocus()

            print(
                "[CEFView] Snapshot captured via container bitmap: \(Int(thumbnailSize.width))x\(Int(thumbnailSize.height))"
            )
            Task { @MainActor in completion(thumbnail) }
            return
        }

        print("[CEFView] All snapshot strategies failed")
        Task { @MainActor in completion(nil) }
    }

    // MARK: - View Lifecycle & Resize Handling

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window != nil {
            print("[CEFView] Attached to window")

            // Create browser if we have a pending URL
            if let url = pendingURL {
                pendingURL = nil
                DispatchQueue.main.async { [weak self] in
                    self?.createBrowserIfNeeded(url: url)
                }
            }
        } else {
            print("[CEFView] Detached from window")
        }
    }

    override func layout() {
        super.layout()

        let size = bounds.size
        guard size.width > 0 && size.height > 0 else { return }

        // Notify CEF of resize if browser exists
        if let handle = cefBrowserHandle {
            print("[CEFView] Layout changed: \(Int(size.width))x\(Int(size.height))")

            // CRITICAL: Sync CEF browser view frame to match container
            // This ensures no gaps during horizontal (height) resizes
            if let browserViewPtr = cef_get_browser_view(handle) {
                let browserView = Unmanaged<NSView>.fromOpaque(browserViewPtr).takeUnretainedValue()
                if browserView.frame != bounds {
                    browserView.frame = bounds
                }
            }

            // Notify CEF that resize started (for smooth reflow)
            notifyMoveOrResizeStarted()

            // Resize the browser view
            cef_resize_browser(handle, Int32(size.width), Int32(size.height))
        }

        // Try to create browser if pending
        if !browserCreated, let url = pendingURL {
            pendingURL = nil
            createBrowserIfNeeded(url: url)
        }
    }

    /// Handle frame change notification for resize tracking
    @objc private func frameDidChange(_ notification: Notification) {
        if cefBrowserHandle != nil {
            // Notify CEF about the resize for proper content reflow
            notifyMoveOrResizeStarted()
        }
    }

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        isResizing = true
        print("[CEFView] Live resize started")

        // Notify CEF that a resize operation is starting
        notifyMoveOrResizeStarted()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        isResizing = false
        print("[CEFView] Live resize ended")

        // Final resize notification
        if let handle = cefBrowserHandle {
            let size = bounds.size
            cef_resize_browser(handle, Int32(size.width), Int32(size.height))
        }
    }

    /// Notify CEF that a move or resize operation has started
    /// This is critical for smooth content reflow during sidebar resize
    private func notifyMoveOrResizeStarted() {
        guard let handle = cefBrowserHandle else { return }

        // CEF's WasResized is called internally by cef_resize_browser
        // For additional smoothness, we can call it here as well
        // The C shim's cef_resize_browser already calls browser->GetHost()->WasResized()

        // Force a synchronous resize for better responsiveness
        let size = bounds.size
        cef_resize_browser(handle, Int32(size.width), Int32(size.height))
    }

    // MARK: - First Responder & Input Handling

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func becomeFirstResponder() -> Bool {
        // Forward focus to CEF browser view if available
        if let browserView = cef_get_browser_view(cefBrowserHandle) {
            let nsView = Unmanaged<NSView>.fromOpaque(browserView).takeUnretainedValue()
            window?.makeFirstResponder(nsView)
            return true
        }
        return super.becomeFirstResponder()
    }
}

// =============================================================================
// MARK: - CEF Display Link Integration (Optional High-Performance Mode)
// =============================================================================

/// Extension for CVDisplayLink-based message loop (higher performance)
extension CEFContainerView {

    /// Start display link for VSync-aligned message loop
    /// Use this instead of timer for smoother rendering
    func startDisplayLinkMessageLoop() {
        guard displayLink == nil else { return }

        var displayLinkRef: CVDisplayLink?
        let result = CVDisplayLinkCreateWithActiveCGDisplays(&displayLinkRef)

        guard result == kCVReturnSuccess, let link = displayLinkRef else {
            print("[CEFView] Failed to create display link, falling back to timer")
            return
        }

        // Set callback
        let callback: CVDisplayLinkOutputCallback = {
            displayLink, now, outputTime, flags, outFlags, context in
            // Dispatch to main thread for CEF work
            DispatchQueue.main.async {
                _ = cef_do_message_work()
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(link, callback, nil)
        CVDisplayLinkStart(link)

        displayLink = link
        messageLoopTimer?.invalidate()
        messageLoopTimer = nil

        print("[CEFView] Display link message loop started")
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
    struct BrowserCanvas_Previews: PreviewProvider {
        static var previews: some View {
            let state = BrowserState()
            if let tab = state.activeTab {
                // Use tab.id as both pageId and parentTabId for non-stack mode preview
                BrowserCanvas(
                    browserState: state, pageId: tab.id, parentTabId: tab.id, url: tab.url
                )
                .frame(width: 800, height: 600)
            }
        }
    }
#endif
