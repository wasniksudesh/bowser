// FloatingDockPanel.swift - NSPanel Subclass for Floating Dock
// Non-activating panel with Spotlight-like behavior

import AppKit
import SwiftUI

// =============================================================================
// MARK: - Floating Dock Panel
// =============================================================================

/// Custom NSPanel for the floating dock widget
/// Implements non-activating Spotlight-like behavior with always-on-top positioning
final class FloatingDockPanel: NSPanel {

    // MARK: - Initialization

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 44),
            styleMask: [.nonactivatingPanel, .resizable, .titled],
            backing: .buffered,
            defer: false
        )

        configurePanel()
    }

    // MARK: - Configuration

    private func configurePanel() {
        // Non-activating Spotlight-like behavior
        self.becomesKeyOnlyIfNeeded = true
        self.hidesOnDeactivate = false

        // Always on top
        self.level = .floating

        // Visible on all Spaces, hide in Mission Control
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Movable between displays
        self.isMovableByWindowBackground = false  // We handle dragging manually
        self.isMovable = true

        // Frameless appearance
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.styleMask.insert(.fullSizeContentView)

        // Semi-transparent background
        self.backgroundColor = .clear
        self.isOpaque = false

        // No traffic lights
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }

    // MARK: - First Responder

    /// Override to accept first responder status when clicked
    override var acceptsFirstResponder: Bool {
        return true
    }

    // MARK: - Window Behavior Overrides

    /// Override to allow becoming key for both search input and CEF browser interaction
    override var canBecomeKey: Bool {
        // Allow becoming key when:
        // 1. Typing in search field (text field is first responder)
        // 2. Interacting with CEF browser in tab preview mode

        // Check if a text field is first responder (search bar)
        if let firstResponder = self.firstResponder {
            if firstResponder is NSTextView || firstResponder is NSTextField {
                return true
            }
        }

        // Check if we're in tab preview mode by looking for CEF views in the hierarchy
        // This allows keyboard input to go to the CEF browser when user clicks on it
        if containsCEFView(in: contentView) {
            return true
        }

        return false
    }

    /// Recursively check if the view hierarchy contains a CEF browser view
    private func containsCEFView(in view: NSView?) -> Bool {
        guard let view = view else { return false }

        // Check if this view is a CEF container
        if NSStringFromClass(type(of: view)).contains("CEF") {
            return true
        }

        // Check subviews recursively
        for subview in view.subviews {
            if containsCEFView(in: subview) {
                return true
            }
        }

        return false
    }

    // MARK: - Event Handling

    /// Override to make panel become key when clicked
    override func sendEvent(_ event: NSEvent) {
        // Make panel key on mouse down to ensure keyboard input works
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            // Only make key if we can become key (based on canBecomeKey logic)
            if canBecomeKey && !isKeyWindow {
                makeKey()
            }
        }

        super.sendEvent(event)
    }
}