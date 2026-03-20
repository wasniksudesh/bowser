// FramelessWindow.swift - Arc-Style Frameless Window (NSWindow Subclass)
// Swift 6.2 with @MainActor isolation for thread safety
// Reusable frameless window component following SOLID principles

import AppKit

// =============================================================================
// MARK: - Frameless Window (NSWindow Subclass)
// =============================================================================

/// Custom NSWindow subclass implementing Arc Browser-style frameless window chrome.
///
/// ## Key Features
/// - **Transparent Titlebar**: Uses `titlebarAppearsTransparent = true` to hide
///   the standard gray titlebar while retaining window controls.
/// - **Full-Size Content View**: Uses `.fullSizeContentView` style mask so
///   content extends edge-to-edge, filling the area behind the titlebar.
/// - **Repositioned Traffic Lights**: Programmatically moves Close/Minimize/Zoom
///   buttons from the standard titlebar position to float inside the sidebar area.
/// - **Configuration-Driven**: Uses `FramelessWindowConfiguration` for customization.
/// - **Layout Config Pattern**: Uses `TrafficLightLayoutConfig` for synchronized positioning.
///
/// ## Architecture (SOLID Principles)
/// - **Single Responsibility**: Window handles only window-level concerns
/// - **Open/Closed**: Extensible via configuration, closed for modification
/// - **Dependency Inversion**: Depends on abstractions (coordinator, layout config)
///
/// ## Traffic Light Synchronization
/// The `TrafficLightLayoutConfig` serves as the **single source of truth** for both:
/// 1. AppKit button positioning (via `applyTrafficLightLayout(_:)`)
/// 2. SwiftUI spacer/padding values (via `reservedWidth`, `reservedHeight`)
///
/// This ensures the SwiftUI sidebar header reserves exactly the right amount of space
/// to avoid overlapping the AppKit traffic light buttons.
///
/// ## Usage
/// ```swift
/// // Create with default Arc browser configuration
/// let window = FramelessWindow.arcStyleWindow()
///
/// // Apply custom layout (shared with SwiftUI)
/// let layoutConfig = TrafficLightLayoutConfig.arcBrowser
/// window.applyTrafficLightLayout(layoutConfig)
/// ```
@MainActor
public final class FramelessWindow: NSWindow, FramelessWindowProtocol {

    // MARK: - Properties

    /// The traffic light state coordinator managing button positions
    public let trafficLightCoordinator: TrafficLightStateCoordinator

    /// Current frameless configuration
    private var framelessConfiguration: FramelessWindowConfiguration

    /// Current traffic light layout configuration (single source of truth)
    public private(set) var currentLayoutConfig: TrafficLightLayoutConfig

    /// Whether traffic lights are currently hidden
    private var trafficLightsHidden: Bool = false

    /// Whether window is currently in fullscreen mode
    public private(set) var isInFullScreen: Bool = false

    // MARK: - Initialization

    /// Initialize a frameless window with configuration.
    ///
    /// - Parameters:
    ///   - contentRect: Initial window frame
    ///   - styleMask: Window style mask (should include .fullSizeContentView)
    ///   - backing: Backing store type
    ///   - defer: Whether to defer window creation
    ///   - configuration: Frameless window configuration
    ///   - coordinator: Traffic light state coordinator
    ///   - layoutConfig: Traffic light layout configuration (single source of truth)
    public init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool,
        configuration: FramelessWindowConfiguration,
        coordinator: TrafficLightStateCoordinator,
        layoutConfig: TrafficLightLayoutConfig = .arcBrowser
    ) {
        self.framelessConfiguration = configuration
        self.trafficLightCoordinator = coordinator
        self.currentLayoutConfig = layoutConfig

        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )

        // Apply configuration
        applyFramelessConfiguration(configuration)

        // Apply layout config (ensures traffic lights use the shared config)
        applyTrafficLightLayout(layoutConfig)

        // Setup coordinator callbacks
        setupCoordinatorBindings()

        // Setup notification observers
        setupWindowObservers()

        // Initial traffic light positioning
        repositionTrafficLights()
    }

    deinit {
        // Observers using self as object are automatically cleaned up
    }

    // MARK: - FramelessWindowProtocol

    /// Apply frameless window configuration.
    public func applyFramelessConfiguration(_ config: FramelessWindowConfiguration) {
        self.framelessConfiguration = config
        FramelessWindowApplicator.apply(to: self, configuration: config)

        // Update coordinator with new traffic light config
        trafficLightCoordinator.applyPreset(config.trafficLightConfiguration)

        // Remove any window toolbar for Arc-style frameless appearance
        removeWindowToolbar()

        // Configure split view dividers after view hierarchy is established
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.configureSplitViewDividers()
            // Also ensure toolbar is removed after SwiftUI has set up
            self?.removeWindowToolbar()
        }
    }

    /// Remove the window toolbar for Arc-style frameless appearance.
    /// NavigationSplitView may create a toolbar by default which we need to hide.
    private func removeWindowToolbar() {
        // Remove the toolbar entirely if it exists
        if toolbar != nil {
            toolbar = nil
        }

        // Ensure the title and toolbar are hidden
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        // Remove titlebar separator for seamless Arc-style
        titlebarSeparatorStyle = .none
    }

    // MARK: - Traffic Light Layout (Single Source of Truth)

    /// Apply a traffic light layout configuration.
    ///
    /// This method accepts a `TrafficLightLayoutConfig` which serves as the **single source
    /// of truth** for both AppKit button positioning and SwiftUI spacer/padding values.
    ///
    /// ## Synchronization Guarantee
    /// When you pass the same `TrafficLightLayoutConfig` to both this method and the
    /// `SidebarHeaderView`, you are guaranteed that:
    /// - The AppKit traffic light buttons will be positioned at `(xOffset, yOffset)`
    /// - The SwiftUI sidebar header will reserve exactly `reservedWidth` x `reservedHeight`
    /// - The sidebar toggle button will appear at `sidebarToggleXPosition`
    ///
    /// - Parameter config: The layout configuration to apply
    public func applyTrafficLightLayout(_ config: TrafficLightLayoutConfig) {
        self.currentLayoutConfig = config

        // Update coordinator to stay in sync
        trafficLightCoordinator.applyPreset(config.toTrafficLightConfiguration())

        // Immediately reposition traffic lights
        repositionTrafficLightsWithLayout(config)

        // Post notification for any SwiftUI views that need to update
        NotificationCenter.default.post(
            name: .trafficLightLayoutDidChange,
            object: self,
            userInfo: ["config": config]
        )
    }

    /// Reposition traffic lights using a specific layout configuration.
    ///
    /// - Parameter config: The layout configuration specifying button positions
    private func repositionTrafficLightsWithLayout(_ config: TrafficLightLayoutConfig) {
        guard !trafficLightsHidden else { return }

        // Get the three standard window buttons
        guard let closeButton = standardWindowButton(.closeButton),
            let minimizeButton = standardWindowButton(.miniaturizeButton),
            let zoomButton = standardWindowButton(.zoomButton)
        else {
            return
        }

        let buttons = [closeButton, minimizeButton, zoomButton]

        // Find the titlebar container view
        guard let titlebarView = findTitlebarContainerView(for: closeButton) else {
            return
        }

        // Calculate button positions using the layout config
        let buttonOrigins = config.calculateButtonOrigins(
            containerHeight: titlebarView.bounds.height,
            isFlipped: titlebarView.isFlipped
        )

        // Apply positions
        for (button, origin) in zip(buttons, buttonOrigins) {
            button.setFrameOrigin(origin)
        }
    }

    /// Reposition traffic lights to their configured positions.
    public func repositionTrafficLights() {
        repositionTrafficLightsWithLayout(currentLayoutConfig)
    }

    /// Set traffic light visibility.
    public func setTrafficLightsVisible(_ visible: Bool) {
        // Guard against setting the same value to prevent infinite recursion
        // The coordinator's didSet triggers onVisibilityChanged callback which calls this method
        guard trafficLightCoordinator.isVisible != visible else { return }

        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

        for buttonType in buttonTypes {
            standardWindowButton(buttonType)?.isHidden = !visible
        }

        trafficLightsHidden = !visible
        trafficLightCoordinator.isVisible = visible
    }

    // MARK: - Private Methods

    /// Setup bindings between coordinator and window.
    private func setupCoordinatorBindings() {
        // When coordinator configuration changes, reposition buttons
        trafficLightCoordinator.onConfigurationChanged = { [weak self] _ in
            self?.repositionTrafficLights()
        }

        // When coordinator visibility changes, update buttons
        trafficLightCoordinator.onVisibilityChanged = { [weak self] visible in
            self?.setTrafficLightsVisible(visible)
        }

        // When fullscreen state changes
        trafficLightCoordinator.onFullScreenChanged = { [weak self] isFullScreen in
            self?.handleCoordinatorFullScreenChange(isFullScreen)
        }
    }

    /// Find the titlebar container view for positioning.
    private func findTitlebarContainerView(for button: NSView) -> NSView? {
        // Try to get the titlebar container (superview of superview)
        if let containerView = button.superview?.superview {
            return containerView
        }
        // Fallback to direct superview
        return button.superview
    }

    /// Setup notification observers for window events.
    private func setupWindowObservers() {
        let center = NotificationCenter.default

        // Reposition on resize
        center.addObserver(
            self,
            selector: #selector(handleWindowDidResize),
            name: NSWindow.didResizeNotification,
            object: self
        )

        // Handle fullscreen transitions
        center.addObserver(
            self,
            selector: #selector(handleWillEnterFullScreen),
            name: NSWindow.willEnterFullScreenNotification,
            object: self
        )

        center.addObserver(
            self,
            selector: #selector(handleDidEnterFullScreen),
            name: NSWindow.didEnterFullScreenNotification,
            object: self
        )

        center.addObserver(
            self,
            selector: #selector(handleDidExitFullScreen),
            name: NSWindow.didExitFullScreenNotification,
            object: self
        )

        // Handle window becoming key
        center.addObserver(
            self,
            selector: #selector(handleWindowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: self
        )
    }

    /// Configure split view dividers to be invisible.
    private func configureSplitViewDividers() {
        guard let contentView = contentView else { return }
        configureSplitViewsRecursively(in: contentView)

        // Also configure NSSplitViewController items for no titlebar separator
        configureSplitViewControllerItems()
    }

    /// Configure NSSplitViewController items to remove titlebar separators.
    /// This is critical for Arc-style UI where we want no header in the sidebar.
    private func configureSplitViewControllerItems() {
        guard let contentViewController = contentViewController else { return }
        findAndConfigureSplitViewController(in: contentViewController)
    }

    /// Recursively search for and configure NSSplitViewController
    private func findAndConfigureSplitViewController(in viewController: NSViewController) {
        if let splitViewController = viewController as? NSSplitViewController {
            for item in splitViewController.splitViewItems {
                // Remove titlebar separator for all split view items
                item.titlebarSeparatorStyle = .none
            }
        }

        // Search in children
        for child in viewController.children {
            findAndConfigureSplitViewController(in: child)
        }

        // Search in presented view controller
        if let presented = viewController.presentedViewControllers {
            for presentedVC in presented {
                findAndConfigureSplitViewController(in: presentedVC)
            }
        }
    }

    private func configureSplitViewsRecursively(in view: NSView) {
        if let splitView = view as? NSSplitView {
            splitView.dividerStyle = .thin
            splitView.setValue(NSColor.clear, forKey: "dividerColor")
            hideInternalDividerViews(in: splitView)
            splitView.needsDisplay = true
        }

        for subview in view.subviews {
            configureSplitViewsRecursively(in: subview)
        }
    }

    private func hideInternalDividerViews(in view: NSView) {
        let className = String(describing: type(of: view))

        if className.contains("Divider")
            || (className.contains("_TtC") && className.contains("Split"))
        {
            view.isHidden = true
            view.alphaValue = 0
        }

        // Check for thin views that could be dividers
        if view.frame.width > 0 && view.frame.width <= 2 && view.frame.height > 50 {
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.alphaValue = 0
        }
        if view.frame.height > 0 && view.frame.height <= 2 && view.frame.width > 50 {
            view.layer?.backgroundColor = NSColor.clear.cgColor
            view.alphaValue = 0
        }

        for subview in view.subviews {
            hideInternalDividerViews(in: subview)
        }
    }

    private func handleCoordinatorFullScreenChange(_ isFullScreen: Bool) {
        // Coordinator handles configuration changes
        // We just need to reposition after the change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.repositionTrafficLights()
        }
    }

    // MARK: - Layout Overrides

    public override func layoutIfNeeded() {
        super.layoutIfNeeded()
        if framelessConfiguration.autoRepositionTrafficLights {
            repositionTrafficLights()
        }
    }

    public override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)

        // Ensure traffic lights are correctly positioned after window appears
        DispatchQueue.main.async { [weak self] in
            self?.repositionTrafficLights()
        }
    }

    public override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        if framelessConfiguration.autoRepositionTrafficLights {
            repositionTrafficLights()
        }
    }

    public override func setFrame(
        _ frameRect: NSRect, display displayFlag: Bool, animate animateFlag: Bool
    ) {
        super.setFrame(frameRect, display: displayFlag, animate: animateFlag)
        if framelessConfiguration.autoRepositionTrafficLights {
            repositionTrafficLights()
        }
    }

    // MARK: - Notification Handlers

    @objc private func handleWindowDidResize(_ notification: Notification) {
        if framelessConfiguration.autoRepositionTrafficLights {
            repositionTrafficLights()
        }
    }

    @objc private func handleWillEnterFullScreen(_ notification: Notification) {
        isInFullScreen = true
        trafficLightCoordinator.isFullScreen = true

        // Keep traffic lights visible in fullscreen (Arc-style)
        setTrafficLightsVisible(true)

        // Apply fullscreen layout configuration
        applyTrafficLightLayout(.fullscreen)

        // Post notification for SwiftUI to update layout
        NotificationCenter.default.post(name: .framelessWindowDidEnterFullScreen, object: self)
    }

    @objc private func handleDidEnterFullScreen(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.repositionTrafficLights()
        }
    }

    @objc private func handleDidExitFullScreen(_ notification: Notification) {
        isInFullScreen = false
        trafficLightCoordinator.isFullScreen = false

        setTrafficLightsVisible(true)

        // Restore default layout configuration
        applyTrafficLightLayout(.arcBrowser)

        // Post notification for SwiftUI
        NotificationCenter.default.post(name: .framelessWindowDidExitFullScreen, object: self)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.repositionTrafficLights()
        }
    }

    @objc private func handleWindowDidBecomeKey(_ notification: Notification) {
        repositionTrafficLights()
    }
}

// =============================================================================
// MARK: - Factory Methods
// =============================================================================

extension FramelessWindow {

    /// Create an Arc-style browser window with default configuration.
    ///
    /// - Parameters:
    ///   - contentRect: Initial window frame (defaults to 1280x800)
    ///   - coordinator: Optional traffic light coordinator (creates new if nil)
    ///   - layoutConfig: Traffic light layout configuration (defaults to .arcBrowser)
    /// - Returns: Configured FramelessWindow instance
    public static func arcStyleWindow(
        contentRect: NSRect = NSRect(x: 0, y: 0, width: 1280, height: 800),
        coordinator: TrafficLightStateCoordinator? = nil,
        layoutConfig: TrafficLightLayoutConfig = .arcBrowser
    ) -> FramelessWindow {
        return createWindow(
            configuration: .arcBrowser,
            contentRect: contentRect,
            coordinator: coordinator,
            layoutConfig: layoutConfig
        )
    }

    /// Create a DevTools window.
    ///
    /// - Parameters:
    ///   - contentRect: Initial window frame (defaults to 900x700)
    ///   - coordinator: Optional traffic light coordinator
    ///   - layoutConfig: Traffic light layout configuration (defaults to .compactUtility)
    /// - Returns: Configured FramelessWindow instance
    public static func devToolsWindow(
        contentRect: NSRect = NSRect(x: 0, y: 0, width: 900, height: 700),
        coordinator: TrafficLightStateCoordinator? = nil,
        layoutConfig: TrafficLightLayoutConfig = .compactUtility
    ) -> FramelessWindow {
        return createWindow(
            configuration: .devTools,
            contentRect: contentRect,
            coordinator: coordinator,
            layoutConfig: layoutConfig
        )
    }

    /// Create a settings window with compact configuration.
    ///
    /// - Parameters:
    ///   - contentRect: Initial window frame (defaults to 700x500)
    ///   - coordinator: Optional traffic light coordinator
    ///   - layoutConfig: Traffic light layout configuration (defaults to .compactUtility)
    /// - Returns: Configured FramelessWindow instance
    public static func settingsWindow(
        contentRect: NSRect = NSRect(x: 0, y: 0, width: 700, height: 500),
        coordinator: TrafficLightStateCoordinator? = nil,
        layoutConfig: TrafficLightLayoutConfig = .compactUtility
    ) -> FramelessWindow {
        return createWindow(
            configuration: .settings,
            contentRect: contentRect,
            coordinator: coordinator,
            layoutConfig: layoutConfig
        )
    }


    /// Create a frameless window with custom configuration.
    ///
    /// - Parameters:
    ///   - configuration: The frameless window configuration
    ///   - contentRect: Initial window frame
    ///   - coordinator: Optional traffic light coordinator (creates new if nil)
    ///   - layoutConfig: Traffic light layout configuration
    /// - Returns: Configured FramelessWindow instance
    public static func createWindow(
        configuration: FramelessWindowConfiguration,
        contentRect: NSRect,
        coordinator: TrafficLightStateCoordinator? = nil,
        layoutConfig: TrafficLightLayoutConfig = .arcBrowser
    ) -> FramelessWindow {
        let trafficCoordinator =
            coordinator
            ?? TrafficLightStateCoordinator(
                configuration: configuration.trafficLightConfiguration
            )

        return FramelessWindow(
            contentRect: contentRect,
            styleMask: FramelessStyleMaskBuilder.build(),
            backing: .buffered,
            defer: false,
            configuration: configuration,
            coordinator: trafficCoordinator,
            layoutConfig: layoutConfig
        )
    }
}

// =============================================================================
// MARK: - Notification Names
// =============================================================================

extension Notification.Name {
    /// Posted when a frameless window enters fullscreen mode
    public static let framelessWindowDidEnterFullScreen = Notification.Name(
        "Bowser.framelessWindowDidEnterFullScreen")

    /// Posted when a frameless window exits fullscreen mode
    public static let framelessWindowDidExitFullScreen = Notification.Name(
        "Bowser.framelessWindowDidExitFullScreen")

    /// Posted when the traffic light layout configuration changes
    public static let trafficLightLayoutDidChange = Notification.Name(
        "Bowser.trafficLightLayoutDidChange")
}
