// SplitCanvasViewController.swift - NSSplitView-Based Split Editor Container
// Bowser - Swift 6.2
// VS Code-style infinitely nestable split view with drag-and-drop support

import AppKit
import CEFWrapper
import Combine
import UniformTypeIdentifiers

// =============================================================================
// MARK: - Drop Target View
// =============================================================================

/// Custom NSView that acts as a drop target and prevents window dragging during drops.
/// This is critical for proper drag-and-drop behavior when `isMovableByWindowBackground` is true.
class DropTargetView: NSView {

    /// Weak reference to the drag delegate (typically a view controller)
    weak var dragDelegate: NSDraggingDestination?

    /// Whether this view is an invisible interceptor (only handles drags, passes through other events)
    var isInterceptorOnly: Bool = false

    override var mouseDownCanMoveWindow: Bool {
        // Prevent this view from initiating window drags
        // This allows drag-and-drop to work properly
        return false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // If this is an interceptor-only view, pass through all mouse events
        // by returning the sibling view underneath us (typically the browser view)
        if isInterceptorOnly {
            // Find the view below us in the superview's hierarchy
            guard let superview = superview else { return nil }

            // Convert point to superview coordinates
            let pointInSuperview = superview.convert(point, from: self)

            // Find the sibling view at this point (excluding ourselves)
            for sibling in superview.subviews where sibling !== self {
                let pointInSibling = sibling.convert(pointInSuperview, from: superview)
                if sibling.bounds.contains(pointInSibling) {
                    // Recursively hit test into the sibling
                    if let hit = sibling.hitTest(pointInSibling) {
                        return hit
                    }
                    return sibling
                }
            }
            return nil
        }
        return super.hitTest(point)
    }

    // MARK: - NSDraggingDestination Forwarding

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return dragDelegate?.draggingEntered?(sender) ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        return dragDelegate?.draggingUpdated?(sender) ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dragDelegate?.draggingExited?(sender)
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        return dragDelegate?.prepareForDragOperation?(sender) ?? false
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        return dragDelegate?.performDragOperation?(sender) ?? false
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        dragDelegate?.concludeDragOperation?(sender)
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        dragDelegate?.draggingEnded?(sender)
    }
}

// =============================================================================
// MARK: - Pane Controls View
// =============================================================================

/// Overlay view with close and expand buttons for split panes.
/// Appears on hover at the top-right corner of each pane.
@MainActor
final class PaneControlsView: NSView {

    // MARK: - Callbacks

    /// Called when close button is pressed
    var onClose: (() -> Void)?

    /// Called when expand button is pressed
    var onExpand: (() -> Void)?

    // MARK: - Views

    private var closeButton: NSButton!
    private var expandButton: NSButton!
    private var containerView: NSVisualEffectView!

    // MARK: - State

    private var trackingArea: NSTrackingArea?
    private var isHoveringPane: Bool = false {
        didSet {
            updateVisibility()
        }
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true

        // Translucent background container
        containerView = NSVisualEffectView()
        containerView.material = .hudWindow
        containerView.blendingMode = .withinWindow
        containerView.state = .active
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 6
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        // Close button
        closeButton = createButton(
            symbolName: "xmark",
            tooltip: "Close split pane",
            action: #selector(closeButtonClicked)
        )
        containerView.addSubview(closeButton)

        // Expand button (pop out to single view)
        expandButton = createButton(
            symbolName: "arrow.up.left.and.arrow.down.right",
            tooltip: "Expand to single view",
            action: #selector(expandButtonClicked)
        )
        containerView.addSubview(expandButton)

        // Layout
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            expandButton.leadingAnchor.constraint(
                equalTo: containerView.leadingAnchor, constant: 4),
            expandButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            expandButton.widthAnchor.constraint(equalToConstant: 22),
            expandButton.heightAnchor.constraint(equalToConstant: 22),

            closeButton.leadingAnchor.constraint(equalTo: expandButton.trailingAnchor, constant: 2),
            closeButton.trailingAnchor.constraint(
                equalTo: containerView.trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),

            containerView.heightAnchor.constraint(equalToConstant: 30),
        ])

        // Initially semi-transparent
        alphaValue = 0.0
    }

    private func createButton(symbolName: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .white
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // MARK: - Actions

    @objc private func closeButtonClicked() {
        onClose?()
    }

    @objc private func expandButtonClicked() {
        onExpand?()
    }

    // MARK: - Hover Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existing = trackingArea {
            removeTrackingArea(existing)
        }

        // Track the entire superview (pane container) for hover
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect,
        ]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHoveringPane = true
    }

    override func mouseExited(with event: NSEvent) {
        isHoveringPane = false
    }

    private func updateVisibility() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = isHoveringPane ? 1.0 : 0.0
        }
    }

    // Also track parent view's hover
    func setParentHovering(_ hovering: Bool) {
        isHoveringPane = hovering
    }
}

// =============================================================================
// MARK: - Split Pane View Controller
// =============================================================================

/// View controller for a single pane in the split layout.
/// Contains a single browser view and handles drop detection for that pane.
@MainActor
final class SplitPaneViewController: NSViewController, NSDraggingDestination, CEFBrowserDelegate {

    // MARK: - Properties

    /// Unique identifier for this pane
    let paneId: UUID

    /// Tab ID displayed in this pane
    private(set) var tabId: UUID

    /// Accessor to get the browser state (set by parent controller)
    var browserStateAccessor: (() -> BrowserState?)?

    /// Callback when a drop occurs
    var onDrop: ((UUID, UUID, SplitDropZone) -> Void)?

    /// Callback when drag enters/updates (for overlay)
    var onDragUpdate: ((UUID, SplitDropZone, NSRect) -> Void)?

    /// Callback when drag exits
    var onDragExit: ((UUID) -> Void)?

    /// Callback when close button is pressed (paneId)
    var onClosePane: ((UUID) -> Void)?

    /// Callback when expand button is pressed (paneId, tabId)
    var onExpandPane: ((UUID, UUID) -> Void)?

    /// Whether this pane is in a split view (shows controls when true)
    var isInSplitView: Bool = false {
        didSet {
            paneControlsView?.isHidden = !isInSplitView
        }
    }

    /// Browser view container
    private var browserContainer: NSView?

    /// Currently highlighted drop zone
    private var currentDropZone: SplitDropZone?

    /// Pane controls overlay view (close/expand buttons)
    private var paneControlsView: PaneControlsView?

    // MARK: - Initialization

    init(paneId: UUID, tabId: UUID) {
        self.paneId = paneId
        self.tabId = tabId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - View Lifecycle

    /// Invisible overlay that intercepts drags above the browser view
    private var dropInterceptor: DropTargetView?

    override func loadView() {
        let container = DropTargetView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Set this controller as the drag delegate
        container.dragDelegate = self

        // Register for drag types - must include all types we want to accept
        container.registerForDraggedTypes([
            .string,
            .bowserTabId,
            NSPasteboard.PasteboardType(UTType.plainText.identifier),
        ])

        view = container
        browserContainer = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Add an invisible overlay above the browser to intercept drags
        // This is needed because CEF views may intercept drag events
        // IMPORTANT: Setup interceptor FIRST, then browser below it
        setupDropInterceptor()

        // Setup browser view from BrowserManager (will be placed below interceptor)
        setupBrowserView()

        // Setup pane controls (close/expand buttons)
        setupPaneControls()
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        // Re-set the drag delegate in case view was recycled
        if let container = view as? DropTargetView {
            container.dragDelegate = self
        }
        if let interceptor = dropInterceptor {
            interceptor.dragDelegate = self
        }
    }

    /// Setup an invisible overlay to intercept drags above the browser
    private func setupDropInterceptor() {
        guard let container = browserContainer else { return }

        let interceptor = DropTargetView()
        interceptor.wantsLayer = true
        interceptor.layer?.backgroundColor = NSColor.clear.cgColor
        interceptor.dragDelegate = self
        interceptor.isInterceptorOnly = true  // Pass through non-drag events

        // Register for drag types
        interceptor.registerForDraggedTypes([
            .string,
            .bowserTabId,
            NSPasteboard.PasteboardType(UTType.plainText.identifier),
        ])

        // Add above all other subviews
        container.addSubview(interceptor, positioned: .above, relativeTo: nil)

        // Fill the container
        interceptor.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            interceptor.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            interceptor.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            interceptor.topAnchor.constraint(equalTo: container.topAnchor),
            interceptor.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.dropInterceptor = interceptor
    }

    /// Setup pane controls overlay (close/expand buttons)
    private func setupPaneControls() {
        guard let container = browserContainer else { return }

        let controlsView = PaneControlsView()
        controlsView.onClose = { [weak self] in
            guard let self = self else { return }
            self.onClosePane?(self.paneId)
        }
        controlsView.onExpand = { [weak self] in
            guard let self = self else { return }
            self.onExpandPane?(self.paneId, self.tabId)
        }

        // Add above all other subviews
        container.addSubview(controlsView, positioned: .above, relativeTo: nil)

        // Position at top-right corner
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controlsView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            controlsView.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
        ])

        // Initially hidden if not in split view
        controlsView.isHidden = !isInSplitView
        self.paneControlsView = controlsView

        // Setup hover tracking on the entire container
        setupHoverTracking(for: controlsView)
    }

    /// Hover tracking area for the container
    private var containerTrackingArea: NSTrackingArea?

    /// Setup hover tracking on the container to show/hide pane controls
    private func setupHoverTracking(for controlsView: PaneControlsView) {
        guard let container = browserContainer else { return }

        // Remove existing tracking area if any
        if let existing = containerTrackingArea {
            container.removeTrackingArea(existing)
        }

        // Create new tracking area for the entire container
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect,
        ]
        containerTrackingArea = NSTrackingArea(
            rect: container.bounds, options: options, owner: self, userInfo: nil)
        container.addTrackingArea(containerTrackingArea!)
    }

    // Override to handle mouse tracking
    override func mouseEntered(with event: NSEvent) {
        paneControlsView?.setParentHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        paneControlsView?.setParentHovering(false)
    }

    // MARK: - Browser Management

    /// The currently displayed browser view (if any)
    private weak var currentBrowserView: CEFContainerView?

    /// Setup or reparent the browser view for this pane's tab
    private func setupBrowserView() {
        guard let container = browserContainer else {
            print("[SplitPaneVC] No container for browser setup")
            return
        }

        print("[SplitPaneVC] Setting up browser for tab: \(tabId)")

        // Get the actual tab URL from browser state
        let tabURL: URL
        if let browserState = browserStateAccessor?(),
            let tab = browserState.tabManager.tab(for: tabId)
        {
            tabURL = tab.activePaneURL
            print("[SplitPaneVC] Using tab URL: \(tabURL)")
        } else {
            tabURL = URL(string: "https://www.google.com")!
            print("[SplitPaneVC] No browser state access, using google.com")
        }

        // Get or create browser from BrowserManager
        // Pass self as delegate to receive title/favicon/preview callbacks
        // In pane mode (non-stack), tabId serves as both pageId and parentTabId
        let browserView = BrowserManager.shared.getBrowser(
            for: tabId,
            url: tabURL,
            delegate: self,
            parentTabId: tabId
        )

        print("[SplitPaneVC] Got browser view: \(browserView.identifier?.rawValue ?? "no-id")")

        // If same browser view is already displayed, no action needed
        if browserView === currentBrowserView && browserView.superview === container {
            print("[SplitPaneVC] Browser view already in place")
            return
        }

        // Remove the previous browser view from this container (but don't destroy it)
        // This is critical: when switching tabs, we need to detach the old browser
        // so the new one can be displayed
        if let oldBrowser = currentBrowserView, oldBrowser !== browserView {
            print("[SplitPaneVC] Removing old browser view from container")
            oldBrowser.removeFromSuperview()
        }

        // Reparent the new browser view if needed
        if browserView.superview !== container {
            print("[SplitPaneVC] Reparenting browser view to container")
            browserView.removeFromSuperview()

            // Add browser view at the bottom of the view hierarchy
            if let interceptor = dropInterceptor {
                container.addSubview(browserView, positioned: .below, relativeTo: interceptor)
            } else {
                container.addSubview(browserView)
            }

            browserView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                browserView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                browserView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                browserView.topAnchor.constraint(equalTo: container.topAnchor),
                browserView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        // Track the current browser view
        currentBrowserView = browserView

        // Ensure drop interceptor stays on top
        if let interceptor = dropInterceptor {
            container.addSubview(interceptor, positioned: .above, relativeTo: nil)
        }
    }

    /// Update to display a different tab
    func updateTab(_ newTabId: UUID) {
        guard newTabId != tabId else { return }
        tabId = newTabId
        setupBrowserView()
    }

    /// Notify the browser view that a split resize operation is starting.
    /// Called from RecursiveSplitViewController when split divider drag begins.
    func notifySplitResizeStarted() {
        currentBrowserView?.notifySplitResizeStarted()
    }

    // MARK: - NSDraggingDestination

    func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        print("[SplitPaneVC] draggingEntered for pane \(paneId)")

        guard extractTabId(from: sender) != nil else {
            print("[SplitPaneVC] No tab ID found in pasteboard")
            return []
        }

        let point = view.convert(sender.draggingLocation, from: nil)
        let zone = DropZoneDetector.detectZone(point: point, in: view.bounds)
        currentDropZone = zone

        print("[SplitPaneVC] Detected zone: \(zone) at point \(point)")
        onDragUpdate?(paneId, zone, view.bounds)

        return .move
    }

    func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard extractTabId(from: sender) != nil else {
            return []
        }

        let point = view.convert(sender.draggingLocation, from: nil)
        let zone = DropZoneDetector.detectZone(point: point, in: view.bounds)

        if zone != currentDropZone {
            currentDropZone = zone
            print("[SplitPaneVC] Zone updated: \(zone)")
            onDragUpdate?(paneId, zone, view.bounds)
        }

        return .move
    }

    func draggingExited(_ sender: (any NSDraggingInfo)?) {
        print("[SplitPaneVC] draggingExited for pane \(paneId)")
        currentDropZone = nil
        onDragExit?(paneId)
    }

    func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        print("[SplitPaneVC] performDragOperation for pane \(paneId)")

        guard let droppedTabId = extractTabId(from: sender),
            let zone = currentDropZone
        else {
            print("[SplitPaneVC] Cannot perform drop - missing tab ID or zone")
            return false
        }

        print("[SplitPaneVC] Dropping tab \(droppedTabId) at zone \(zone)")
        onDrop?(paneId, droppedTabId, zone)
        currentDropZone = nil

        return true
    }

    func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let canAccept = extractTabId(from: sender) != nil
        print("[SplitPaneVC] prepareForDragOperation: \(canAccept)")
        return canAccept
    }

    // MARK: - Helpers

    /// Extract tab ID from drag pasteboard
    private func extractTabId(from sender: NSDraggingInfo) -> UUID? {
        let pasteboard = sender.draggingPasteboard

        // Try custom tab ID type first
        if let data = pasteboard.data(forType: .bowserTabId),
            let uuidString = String(data: data, encoding: .utf8),
            let uuid = UUID(uuidString: uuidString)
        {
            return uuid
        }

        // Fall back to string type (UUID string)
        if let uuidString = pasteboard.string(forType: .string),
            let uuid = UUID(uuidString: uuidString)
        {
            return uuid
        }

        return nil
    }

    // MARK: - CEFBrowserDelegate Implementation

    func browserDidChangeLoadingState(
        isLoading: Bool, canGoBack: Bool, canGoForward: Bool, url: URL?
    ) {
        print(
            "[SplitPaneVC] Loading state changed: isLoading=\(isLoading), url=\(url?.absoluteString ?? "nil")"
        )
        guard let browserState = browserStateAccessor?() else { return }

        // Only update if this pane's tab is the active tab
        if browserState.activeTab?.id == tabId {
            browserState.updateActiveTab(
                url: url, isLoading: isLoading, canGoBack: canGoBack, canGoForward: canGoForward)
        }

        // Dismiss the black loading overlay on first successful page load
        currentBrowserView?.setLoadingState(isLoading)
    }

    func browserDidChangeTitle(_ title: String) {
        print("[SplitPaneVC] Title changed: \(title)")
        guard let browserState = browserStateAccessor?() else { return }

        // Update the tab's title regardless of active state
        browserState.tabManager.updateTab(id: tabId, title: title)
    }

    func browserDidChangeURL(_ url: URL) {
        print("[SplitPaneVC] URL changed: \(url.absoluteString)")
        guard let browserState = browserStateAccessor?() else { return }

        // Only update if this is the active tab
        if browserState.activeTab?.id == tabId {
            browserState.updateActiveTab(url: url)
        }
    }

    func browserDidChangeFaviconURL(_ faviconURL: URL?) {
        print("[SplitPaneVC] Favicon URL changed: \(faviconURL?.absoluteString ?? "nil")")
        guard let browserState = browserStateAccessor?() else { return }
        guard let tab = browserState.tabManager.tab(for: tabId) else { return }

        // Capture values BEFORE async call to prevent race conditions
        // This ensures the favicon update goes to the correct tab even if
        // the user switches tabs during the download
        let capturedTabId = tabId
        let capturedPaneId = tab.activePaneId
        let capturedPageURL = tab.url

        Task { @MainActor in
            let image = await FaviconLoader.shared.downloadFavicon(
                from: faviconURL,
                pageURL: capturedPageURL
            )

            // Verify the tab still exists and update using captured IDs
            // This prevents updating the wrong tab if user switched tabs
            guard browserState.tabManager.tab(for: capturedTabId) != nil else {
                print("[SplitPaneVC] Tab \(capturedTabId) no longer exists, discarding favicon")
                return
            }

            browserState.updatePaneIcon(paneId: capturedPaneId, icon: image)
            print("[SplitPaneVC] Favicon updated for tab \(capturedTabId)")
        }
    }

    func browserDidCapturePreview(_ preview: NSImage) {
        print("[SplitPaneVC] Preview captured for tab \(tabId)")
        guard let browserState = browserStateAccessor?() else { return }
        browserState.updateTabPreview(tabId: tabId, preview: preview)
    }

    func browserDidRequestOpenLinkAsChildTab(_ url: URL, parentTabId: UUID) {
        print("[SplitPaneVC] Opening link as child tab: \(url), parentTabId: \(parentTabId)")
        guard let browserState = browserStateAccessor?() else { return }

        // CRITICAL: Use the parentTabId provided by the callback bridge
        // This is the tab ID that OWNS the browser (set at browser creation),
        // NOT the pane's current tabId (which may have changed if user switched tabs)
        _ = browserState.tabManager.createChildTab(
            url: url,
            title: "New Tab",
            parentId: parentTabId
        )

        print("[SplitPaneVC] Created child tab for parent \(parentTabId)")
    }
}

// =============================================================================
// MARK: - Recursive Split View Controller
// =============================================================================

/// View controller that manages an NSSplitView with child panes or nested splits.
/// Supports infinite nesting for VS Code-style split editing.
@MainActor
final class RecursiveSplitViewController: NSSplitViewController {

    // MARK: - Properties

    /// The split node this controller represents
    private(set) var splitNode: SplitNode

    /// Child pane controllers (for leaf nodes)
    private var paneControllers: [UUID: SplitPaneViewController] = [:]

    /// Child split controllers (for nested splits)
    private var childSplitControllers: [UUID: RecursiveSplitViewController] = [:]

    /// Callback when drop occurs in any child pane
    var onDrop: ((UUID, UUID, SplitDropZone) -> Void)?

    /// Callback for drag updates
    var onDragUpdate: ((UUID, SplitDropZone, NSRect) -> Void)?

    /// Callback for drag exit
    var onDragExit: ((UUID) -> Void)?

    /// Callback when close is pressed on a pane
    var onClosePane: ((UUID) -> Void)?

    /// Callback when expand is pressed on a pane (paneId, tabId)
    var onExpandPane: ((UUID, UUID) -> Void)?

    /// Accessor to get the browser state (set by parent controller)
    var browserStateAccessor: (() -> BrowserState?)?

    // MARK: - Initialization

    init(node: SplitNode) {
        self.splitNode = node
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.dividerStyle = .thin
        splitView.autosaveName = nil  // Don't autosave - we manage state

        // Ensure the split view doesn't block window dragging for empty areas
        // but still allows child views to receive drags
        splitView.wantsLayer = true

        // Register for drag types on the split view itself
        splitView.registerForDraggedTypes([
            .string,
            .bowserTabId,
            NSPasteboard.PasteboardType(UTType.plainText.identifier),
        ])

        // Register for split view resize notifications to notify CEF views
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSplitViewWillResize(_:)),
            name: NSSplitView.willResizeSubviewsNotification,
            object: splitView
        )

        rebuildLayout()
    }

    /// Handle split view resize notification - notify all CEF views
    @objc private func handleSplitViewWillResize(_ notification: Notification) {
        notifyAllSplitResizeStarted()
    }

    // MARK: - Layout Management

    /// Update the split node and rebuild layout
    func update(node: SplitNode) {
        self.splitNode = node
        rebuildLayout()
    }

    /// Rebuild the split view layout from the current node
    private func rebuildLayout() {
        // Remove existing split items
        while !splitViewItems.isEmpty {
            removeSplitViewItem(splitViewItems[0])
        }
        paneControllers.removeAll()
        childSplitControllers.removeAll()

        switch splitNode {
        case .pane(let paneId, let tabId):
            // Single pane - shouldn't be in a RecursiveSplitViewController
            // but handle gracefully
            let paneVC = createPaneController(paneId: paneId, tabId: tabId)
            let item = NSSplitViewItem(viewController: paneVC)
            item.minimumThickness = 200
            item.holdingPriority = .defaultLow
            addSplitViewItem(item)

        case .split(_, let axis, let children, let proportions):
            // Configure split orientation
            splitView.isVertical = axis.isNSSplitViewVertical

            // Add children
            for (index, child) in children.enumerated() {
                let childVC: NSViewController

                switch child {
                case .pane(let paneId, let tabId):
                    childVC = createPaneController(paneId: paneId, tabId: tabId)

                case .split:
                    let splitVC = RecursiveSplitViewController(node: child)
                    splitVC.browserStateAccessor = browserStateAccessor  // Pass through browser state access
                    splitVC.onDrop = { [weak self] paneId, tabId, zone in
                        self?.onDrop?(paneId, tabId, zone)
                    }
                    splitVC.onDragUpdate = { [weak self] paneId, zone, bounds in
                        self?.onDragUpdate?(paneId, zone, bounds)
                    }
                    splitVC.onDragExit = { [weak self] paneId in
                        self?.onDragExit?(paneId)
                    }
                    splitVC.onClosePane = { [weak self] paneId in
                        self?.onClosePane?(paneId)
                    }
                    splitVC.onExpandPane = { [weak self] paneId, tabId in
                        self?.onExpandPane?(paneId, tabId)
                    }
                    childSplitControllers[child.id] = splitVC
                    childVC = splitVC
                }

                let item = NSSplitViewItem(viewController: childVC)
                item.minimumThickness = 200
                item.holdingPriority = .defaultLow
                addSplitViewItem(item)

                // Apply proportions after adding (via constraints)
                if index < proportions.count {
                    // Store proportion for later use in delegate
                }
            }

            // Store proportions to apply after layout
            self.pendingProportions = proportions

            // Apply proportions after layout using multiple async cycles
            // to ensure the view has been laid out properly
            DispatchQueue.main.async { [weak self] in
                self?.applyPendingProportions()
            }
        }
    }

    /// Proportions to apply after the view is laid out
    private var pendingProportions: [CGFloat]?

    /// Apply pending proportions if they exist
    private func applyPendingProportions() {
        guard let proportions = pendingProportions else { return }

        // Check if we have valid bounds
        let totalSize: CGFloat
        if splitView.isVertical {
            totalSize = splitView.bounds.width
        } else {
            totalSize = splitView.bounds.height
        }

        if totalSize > 0 {
            applyProportions(proportions)
            pendingProportions = nil
        } else {
            // Bounds not ready yet, try again after layout
            DispatchQueue.main.async { [weak self] in
                self?.applyPendingProportions()
            }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Apply pending proportions if we have them
        if pendingProportions != nil {
            applyPendingProportions()
        }
    }

    /// Recursively notify all panes that a resize operation is starting
    func notifyAllSplitResizeStarted() {
        for (_, paneVC) in paneControllers {
            paneVC.notifySplitResizeStarted()
        }
        for (_, childSplit) in childSplitControllers {
            childSplit.notifyAllSplitResizeStarted()
        }
    }

    /// Create a pane controller for a leaf node
    private func createPaneController(paneId: UUID, tabId: UUID) -> SplitPaneViewController {
        let paneVC = SplitPaneViewController(paneId: paneId, tabId: tabId)
        paneVC.browserStateAccessor = browserStateAccessor  // Pass through browser state access
        paneVC.onDrop = { [weak self] paneId, droppedTabId, zone in
            self?.onDrop?(paneId, droppedTabId, zone)
        }
        paneVC.onDragUpdate = { [weak self] paneId, zone, bounds in
            self?.onDragUpdate?(paneId, zone, bounds)
        }
        paneVC.onDragExit = { [weak self] paneId in
            self?.onDragExit?(paneId)
        }
        paneVC.onClosePane = { [weak self] paneId in
            self?.onClosePane?(paneId)
        }
        paneVC.onExpandPane = { [weak self] paneId, tabId in
            self?.onExpandPane?(paneId, tabId)
        }
        // Show controls if there are multiple children (in a split view)
        paneVC.isInSplitView = splitNode.allTabIds.count > 1
        paneControllers[paneId] = paneVC
        return paneVC
    }

    /// Apply stored proportions to the split view
    private func applyProportions(_ proportions: [CGFloat]) {
        guard proportions.count == splitViewItems.count else { return }

        // NSSplitView.isVertical refers to the DIVIDER orientation:
        // - isVertical = true  → vertical divider → views side-by-side → use WIDTH
        // - isVertical = false → horizontal divider → views stacked → use HEIGHT
        let totalSize: CGFloat
        if splitView.isVertical {
            totalSize = splitView.bounds.width  // Side-by-side: width determines split
        } else {
            totalSize = splitView.bounds.height  // Stacked: height determines split
        }

        // Apply divider positions without animation for immediate effect
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false

            var position: CGFloat = 0
            for (index, proportion) in proportions.dropLast().enumerated() {
                position += totalSize * proportion
                splitView.setPosition(position, ofDividerAt: index)
            }
        }

        // Force layout update
        splitView.layoutSubtreeIfNeeded()
    }

    // MARK: - Pane Access

    /// Get the pane controller for a given pane ID
    func paneController(for paneId: UUID) -> SplitPaneViewController? {
        if let direct = paneControllers[paneId] {
            return direct
        }

        // Search nested splits
        for (_, childSplit) in childSplitControllers {
            if let found = childSplit.paneController(for: paneId) {
                return found
            }
        }

        return nil
    }

    /// Convert bounds of a pane to this view's coordinate system
    func boundsOfPane(_ paneId: UUID) -> NSRect? {
        guard let paneVC = paneController(for: paneId) else { return nil }
        return view.convert(paneVC.view.bounds, from: paneVC.view)
    }
}

// =============================================================================
// MARK: - Split Canvas View Controller (Main Container)
// =============================================================================

/// The main view controller for the split canvas.
/// Manages the root split layout, drop overlay, and coordinates with BrowserState.
@MainActor
final class SplitCanvasViewController: NSViewController {

    // MARK: - Properties

    /// Layout state
    private let layoutState: SplitLayoutState

    /// Callback to notify SwiftUI of layout changes
    var onLayoutChange: ((SplitNode) -> Void)?

    /// Callback to get browser state updates
    var browserStateAccessor: (() -> BrowserState?)?

    /// Root split view controller
    private var rootSplitController: RecursiveSplitViewController?

    /// Drop overlay manager
    private let dropOverlay = DropOverlayManager()

    /// Subscription storage
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(layoutState: SplitLayoutState) {
        self.layoutState = layoutState
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - View Lifecycle

    override func loadView() {
        let container = DropTargetView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor

        // Register for drag types on the main container too
        container.registerForDraggedTypes([
            .string,
            .bowserTabId,
            NSPasteboard.PasteboardType(UTType.plainText.identifier),
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup initial layout
        rebuildRootLayout()

        // Install drop overlay
        dropOverlay.install(in: view)
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        // Ensure root controller fills view
        rootSplitController?.view.frame = view.bounds
    }

    // MARK: - Layout Management

    /// Rebuild the entire split layout from state
    private func rebuildRootLayout() {
        // Remove existing root
        rootSplitController?.view.removeFromSuperview()
        rootSplitController?.removeFromParent()
        rootSplitController = nil

        // Create new root based on node type
        switch layoutState.root {
        case .pane(let paneId, let tabId):
            // Single pane - create a single-item split controller for consistency
            let rootNode = SplitNode.pane(id: paneId, tabId: tabId)
            let rootVC = RecursiveSplitViewController(node: rootNode)
            setupRootController(rootVC)

        case .split:
            let rootVC = RecursiveSplitViewController(node: layoutState.root)
            setupRootController(rootVC)
        }
    }

    /// Setup a root split controller
    private func setupRootController(_ rootVC: RecursiveSplitViewController) {
        // Pass through the browser state accessor for URL resolution
        rootVC.browserStateAccessor = browserStateAccessor

        rootVC.onDrop = { [weak self] paneId, droppedTabId, zone in
            self?.handleDrop(paneId: paneId, tabId: droppedTabId, zone: zone)
        }
        rootVC.onDragUpdate = { [weak self] paneId, zone, bounds in
            self?.handleDragUpdate(paneId: paneId, zone: zone, paneBounds: bounds)
        }
        rootVC.onDragExit = { [weak self] paneId in
            self?.handleDragExit(paneId: paneId)
        }
        rootVC.onClosePane = { [weak self] paneId in
            self?.handleClosePane(paneId: paneId)
        }
        rootVC.onExpandPane = { [weak self] paneId, tabId in
            self?.handleExpandPane(paneId: paneId, tabId: tabId)
        }

        addChild(rootVC)
        rootVC.view.frame = view.bounds
        rootVC.view.autoresizingMask = [.width, .height]
        view.addSubview(rootVC.view, positioned: .below, relativeTo: dropOverlay.overlayView)

        rootSplitController = rootVC
    }

    /// Update layout when state changes
    func updateLayout() {
        rootSplitController?.update(node: layoutState.root)
    }

    // MARK: - Drop Handling

    /// Handle drag update (show overlay)
    private func handleDragUpdate(paneId: UUID, zone: SplitDropZone, paneBounds: NSRect) {
        layoutState.dropTargetPaneId = paneId
        layoutState.currentDropZone = zone

        // Convert pane bounds to our coordinate system
        guard let paneBoundsInSelf = rootSplitController?.boundsOfPane(paneId) else {
            return
        }

        if dropOverlay.overlayView.currentZone == nil {
            dropOverlay.showDrop(zone: zone, targetBounds: paneBoundsInSelf)
        } else {
            dropOverlay.updateDrop(zone: zone, targetBounds: paneBoundsInSelf)
        }
    }

    /// Handle drag exit (hide overlay)
    private func handleDragExit(paneId: UUID) {
        layoutState.clearDropState()
        dropOverlay.hideDrop()
    }

    /// Handle drop (perform split or tab addition)
    private func handleDrop(paneId: UUID, tabId: UUID, zone: SplitDropZone) {
        print("[SplitCanvas] Drop: tab \(tabId) onto pane \(paneId) at \(zone)")

        // Hide overlay
        dropOverlay.hideDrop()
        layoutState.clearDropState()

        // Check if the dropped tab has stack mode enabled
        if let browserState = browserStateAccessor?(),
            let tab = browserState.tabManager.tab(for: tabId), tab.stackModeEnabled
        {
            print("[SplitCanvas] Cannot split - tab \(tabId) has stack mode enabled")
            return
        }

        // Check if the target pane's tab has stack mode enabled
        if let currentTabId = findTabId(for: paneId),
            let browserState = browserStateAccessor?(),
            let currentTab = browserState.tabManager.tab(for: currentTabId),
            currentTab.stackModeEnabled
        {
            print(
                "[SplitCanvas] Cannot split - target pane tab \(currentTabId) has stack mode enabled"
            )
            return
        }

        // Check if the dropped tab is already displayed in this pane
        // If so, do nothing to avoid creating an empty split
        if let currentTabId = findTabId(for: paneId), currentTabId == tabId {
            print(
                "[SplitCanvas] Tab \(tabId) is already displayed in pane \(paneId), ignoring drop")
            return
        }

        // Perform the split
        if zone == .center {
            // Center drop - just focus the pane (tab is already there or handle tab switching)
            layoutState.activePaneId = paneId
        } else {
            // Edge drop - create split
            layoutState.splitPane(paneId: paneId, newTabId: tabId, zone: zone)

            // Rebuild layout
            rebuildRootLayout()

            // Notify SwiftUI
            onLayoutChange?(layoutState.root)
        }
    }

    /// Find the tab ID currently displayed in a specific pane
    private func findTabId(for paneId: UUID) -> UUID? {
        func search(in node: SplitNode) -> UUID? {
            switch node {
            case .pane(let id, let tabId):
                return id == paneId ? tabId : nil
            case .split(_, _, let children, _):
                for child in children {
                    if let found = search(in: child) {
                        return found
                    }
                }
                return nil
            }
        }
        return search(in: layoutState.root)
    }

    // MARK: - Public Interface

    /// Close a pane (removes from split layout only, does NOT close the tab)
    func closePane(_ paneId: UUID) {
        print("[SplitCanvas] Closing pane \(paneId)")
        layoutState.removePane(paneId: paneId)
        rebuildRootLayout()
        onLayoutChange?(layoutState.root)
    }

    /// Handle close pane button press - closes the TAB entirely
    private func handleClosePane(paneId: UUID) {
        // Find the tab ID for this pane
        guard let tabId = findTabId(for: paneId) else {
            print("[SplitCanvas] Close button pressed for pane \(paneId) - no tab ID found")
            return
        }

        print("[SplitCanvas] Close button pressed for pane \(paneId), closing tab \(tabId)")

        // Close the tab via BrowserState - this will:
        // 1. Post tabWillClose notification
        // 2. Remove tab from tab list
        // 3. The tabWillClose notification handler will remove the pane from split
        if let browserState = browserStateAccessor?() {
            browserState.tabManager.closeTab(id: tabId)
        }
    }

    /// Handle expand pane button press - exits split view and shows the tab in single view
    private func handleExpandPane(paneId: UUID, tabId: UUID) {
        print("[SplitCanvas] Expand button pressed for pane \(paneId), tab \(tabId)")

        // Post exitSplitView notification to properly exit split view
        // This will reset to single tab view with the expanded tab
        NotificationCenter.default.post(
            name: .exitSplitView,
            object: nil,
            userInfo: ["tabId": tabId]
        )
    }

    /// Update the tab displayed in a specific pane
    func updatePaneTab(paneId: UUID, tabId: UUID) {
        print("[SplitCanvas] Updating pane \(paneId) to show tab \(tabId)")

        // Find and update the pane controller
        if let paneVC = rootSplitController?.paneController(for: paneId) {
            paneVC.updateTab(tabId)
        }
    }

    /// Reset the split view to a single pane with the given tab
    func resetToSinglePane(paneId: UUID, tabId: UUID) {
        print("[SplitCanvas] Resetting to single pane with tab: \(tabId)")

        // Update layout state to single pane
        layoutState.root = .pane(id: paneId, tabId: tabId)
        layoutState.activePaneId = paneId

        // Rebuild the layout
        rebuildRootLayout()
        onLayoutChange?(layoutState.root)
    }

    /// Restore a split layout from a SplitNode
    func restoreSplitLayout(root: SplitNode) {
        print("[SplitCanvas] Restoring split layout with \(root.allTabIds.count) tabs")

        // Update layout state
        layoutState.root = root

        // Set active pane to first one
        if let firstTabId = root.allTabIds.first {
            layoutState.activePaneId = root.findPane(tabId: firstTabId)
        }

        // Rebuild the layout
        rebuildRootLayout()
        onLayoutChange?(layoutState.root)
    }

    /// Get the current active pane's tab ID
    var activeTabId: UUID? {
        guard let activePaneId = layoutState.activePaneId else {
            return layoutState.root.allTabIds.first
        }

        // Find the tab ID for the active pane
        func findTabId(in node: SplitNode) -> UUID? {
            switch node {
            case .pane(let id, let tabId):
                return id == activePaneId ? tabId : nil
            case .split(_, _, let children, _):
                for child in children {
                    if let found = findTabId(in: child) {
                        return found
                    }
                }
                return nil
            }
        }

        return findTabId(in: layoutState.root)
    }
}
