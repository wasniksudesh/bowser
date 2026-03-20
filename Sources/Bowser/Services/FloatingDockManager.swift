// FloatingDockManager.swift - Lifecycle Manager for Floating Dock
// Handles window creation, keyboard monitoring, click-outside dismissal, and position management

import AppKit
import Combine
import SwiftUI

// =============================================================================
// MARK: - Floating Dock Manager
// =============================================================================

/// Singleton manager for the floating dock widget
/// Handles lifecycle, keyboard shortcuts, and window positioning
@MainActor
final class FloatingDockManager {

    static let shared = FloatingDockManager()

    // MARK: - Properties

    private var dockPanel: FloatingDockPanel?
    private var browserState: BrowserState?
    private var clickMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    // Double-backslash detection
    private var lastBackslashKeyTime: Date?
    private let doubleBackslashInterval: TimeInterval = 0.3

    private init() {}

    // MARK: - Initialization

    func initialize(browserState: BrowserState) {
        self.browserState = browserState
        setupDockPanel()
        setupKeyboardMonitor()
        setupClickOutsideMonitor()
        observeStateChanges()
        observeScreenChanges()

        // Show dock if visible in state
        if browserState.floatingDockState.isVisible {
            show()
        }
    }

    // MARK: - Direct State Binding

    /// Called by state when visibility changes
    func handleVisibilityChange(_ isVisible: Bool) {
        if isVisible {
            show()
        } else {
            hide()
        }
    }

    // MARK: - Panel Setup

    private func setupDockPanel() {
        guard let browserState = browserState else { return }

        let panel = FloatingDockPanel()
        let rootView = FloatingDockRootView(
            browserState: browserState,
            dockState: browserState.floatingDockState
        )
        panel.contentView = NSHostingView(rootView: rootView)

        // Restore saved position or use default
        if let savedPosition = browserState.floatingDockState.dockPosition {
            panel.setFrameOrigin(savedPosition)
        } else {
            centerDockAtTop(panel)
        }

        self.dockPanel = panel

        // Observe window movement for persistence
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification, object: panel)
            // Debounce to avoid excessive writes during drag
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.handlePanelDidMove()
            }
            .store(in: &cancellables)

        // Observe window resize for persistence and state sync
        NotificationCenter.default.publisher(for: NSWindow.didResizeNotification, object: panel)
            .debounce(for: .seconds(0.2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.handlePanelDidResize()
            }
            .store(in: &cancellables)
    }

    private func handlePanelDidMove() {
        guard let panel = dockPanel else { return }
        savePosition(panel.frame.origin)
    }

    private func handlePanelDidResize() {
        guard let panel = dockPanel,
            let dockState = browserState?.floatingDockState
        else { return }

        // Only update state if we are in an expanded mode
        switch dockState.currentState {
        case .tabDropdown, .tabPreview:
            // Update state from window size (minus padding buffer)
            let newWidth = panel.frame.width - 80
            if abs(dockState.previewWidth - newWidth) > 1 {
                dockState.previewWidth = newWidth
            }

            if case .tabPreview = dockState.currentState {
                let newHeight = panel.frame.height - 44 - 80 - 3  // minus header, padding, buffer
                if abs(dockState.previewHeight - newHeight) > 1 {
                    dockState.previewHeight = newHeight
                }
            }
        case .condensed:
            break
        }
    }

    // MARK: - Visibility

    func show() {
        dockPanel?.orderFront(nil)
    }

    func hide() {
        dockPanel?.orderOut(nil)
    }

    func toggleDockVisibility() {
        browserState?.floatingDockState.isVisible.toggle()
    }

    // MARK: - Keyboard Monitoring

    private func setupKeyboardMonitor() {
        // Local monitor (when app is active)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }

        // Global monitor (when app is not active)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            self?.handleKeyEvent(event)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Backslash key code is 42
        guard event.keyCode == 42 else { return }

        // Don't trigger if user is typing in a text field
        if NSApp.keyWindow?.firstResponder is NSTextView
            || NSApp.keyWindow?.firstResponder is NSTextField
        {
            lastBackslashKeyTime = nil
            return
        }

        // Check for double-backslash
        if let lastTime = lastBackslashKeyTime,
            Date().timeIntervalSince(lastTime) < doubleBackslashInterval
        {
            toggleDockVisibility()
            lastBackslashKeyTime = nil
        } else {
            lastBackslashKeyTime = Date()
        }
    }

    // MARK: - Click Outside Monitoring

    private func setupClickOutsideMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            self?.handleClickOutside(event)
        }
    }

    private func handleClickOutside(_ event: NSEvent) {
        guard let panel = dockPanel,
            let dockState = browserState?.floatingDockState
        else { return }

        // Only collapse dropdown, not preview
        // Preview should remain visible even when clicking outside
        guard case .tabDropdown = dockState.currentState else { return }

        // Get click location in screen coordinates
        let clickLocation = NSEvent.mouseLocation
        let panelFrame = panel.frame

        // If click is outside panel, dismiss dropdown
        if !panelFrame.contains(clickLocation) {
            withAnimation(ArcTheme.springAnimation) {
                dockState.currentState = .condensed
            }
        }
    }

    // MARK: - State Observation

    private func observeStateChanges() {
        guard browserState != nil else { return }

        // Observe visibility changes
        NotificationCenter.default.publisher(
            for: NSNotification.Name("FloatingDockVisibilityChanged")
        )
        .sink { [weak self] _ in
            guard let self = self,
                let dockState = self.browserState?.floatingDockState
            else { return }

            if dockState.isVisible {
                self.show()
            } else {
                self.hide()
            }
        }
        .store(in: &cancellables)

        // Observe UI state changes to resize panel
        NotificationCenter.default.publisher(for: NSNotification.Name("FloatingDockStateChanged"))
            .sink { [weak self] _ in
                self?.updatePanelSize()
            }
            .store(in: &cancellables)
    }

    // MARK: - Panel Size Management

    func updatePanelSize() {
        guard let panel = dockPanel,
            let dockState = browserState?.floatingDockState
        else { return }

        // Calculate dynamic width based on state
        let newWidth: CGFloat = calculatePanelWidth(for: dockState.currentState)
        var newHeight: CGFloat = 44  // Base dock height

        switch dockState.currentState {
        case .condensed:
            break
        case .tabDropdown:
            newHeight += 350  // Search + list + link
        case .tabPreview:
            newHeight += dockState.previewHeight + 3  // Preview + resize handle
        }

        // Add small buffer to prevent visual artifacts
        newHeight += 80  // Account for padding (40px top + 40px bottom)

        var frame = panel.frame

        // Calculate new origin to keep panel centered horizontally
        let widthDelta = newWidth - frame.size.width
        frame.origin.x -= widthDelta / 2  // Keep centered

        // Keep top anchored when height changes
        let heightDelta = newHeight - frame.size.height
        frame.origin.y -= heightDelta

        frame.size.width = newWidth
        frame.size.height = newHeight

        // Use smooth animation with display updates to prevent ghosting
        panel.setFrame(frame, display: true, animate: true)
    }

    /// Calculate the appropriate panel width based on dock state
    private func calculatePanelWidth(for state: FloatingDockState.DockUIState) -> CGFloat {
        switch state {
        case .condensed:
            // Condensed state: just the icon bar
            // Approximate: 5 icons × 28px + 1 search button × 36px + spacing + padding
            // = (5 × 28) + 36 + (6 × 8 spacing) + (2 × 12 padding) + 20 (close button)
            return 280 + 80  // Add 80px for padding buffer
        case .tabDropdown, .tabPreview:
            // Expanded state: use user-defined preview width
            let contentWidth = browserState?.floatingDockState.previewWidth ?? 600
            return contentWidth + 80  // Add 80px for padding buffer
        }
    }

    // MARK: - Position Management

    func savePosition(_ position: NSPoint) {
        browserState?.floatingDockState.dockPosition = position
    }

    private func centerDockAtTop(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.visibleFrame
        // Use condensed width for initial positioning
        let panelWidth: CGFloat = 360  // Condensed state width (280 + 80 buffer)
        let panelHeight: CGFloat = 124  // Base height (44) + padding buffer (80)

        let x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
        let y = screenFrame.maxY - panelHeight - 120  // 120pt from top (Spotlight style)

        panel.setFrame(
            NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            display: true
        )
    }

    // MARK: - Multi-Display Support

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.validatePanelPosition()
            }
        }
    }

    private func validatePanelPosition() {
        guard let panel = dockPanel else { return }

        let panelFrame = panel.frame
        let isOnScreen = NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(panelFrame)
        }

        if !isOnScreen {
            // Reset to main screen top
            centerDockAtTop(panel)
        }
    }

}
