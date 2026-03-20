// FloatingDockState.swift - Observable State for Floating Dock
// Manages dock visibility, UI state, position, and preview settings

import Foundation
import SwiftUI

// =============================================================================
// MARK: - Floating Dock State
// =============================================================================

/// Observable state for the floating dock widget
/// Manages visibility, UI state transitions, position persistence, and preview settings
@Observable
@MainActor
final class FloatingDockState {

    // MARK: - Visibility

    /// Whether the dock is currently visible
    var isVisible: Bool = true {
        didSet {
            if isVisible != oldValue {
                saveState()
                // Notify manager directly
                FloatingDockManager.shared.handleVisibilityChange(isVisible)
            }
        }
    }

    // MARK: - UI State

    /// Current UI state of the dock
    enum DockUIState: Equatable {
        case condensed
        case tabDropdown
        case tabPreview(tabId: UUID)
    }

    var currentState: DockUIState = .condensed

    // MARK: - Quick Access Apps

    /// Currently selected quick-access app (YouTube, ChatGPT, WhatsApp, Gmail)
    var selectedQuickAccessApp: String? = nil

    /// Map of app name to tab ID for persisting quick access tabs
    var quickAccessTabs: [String: UUID] = [:]

    // MARK: - Position

    /// Saved dock position (nil = use default centered position)
    var dockPosition: CGPoint? {
        didSet {
            if dockPosition != oldValue {
                savePosition()
            }
        }
    }

    // MARK: - Preview Settings

    /// Height of the tab preview (user-resizable)
    var previewHeight: CGFloat = 400 {
        didSet {
            if previewHeight != oldValue {
                saveState()
            }
        }
    }

    /// Width of the tab preview (user-resizable)
    var previewWidth: CGFloat = 600 {
        didSet {
            if previewWidth != oldValue {
                saveState()
                // Notify manager to resize panel
                NotificationCenter.default.post(
                    name: NSNotification.Name("FloatingDockStateChanged"), object: nil)
            }
        }
    }

    // MARK: - Search

    /// Search query for tab dropdown filtering
    var tabSearchQuery: String = ""

    // MARK: - Dock Search Bar

    /// Whether the dock search bar is expanded
    var isSearchExpanded: Bool = false

    /// Search text in the dock search bar
    var dockSearchText: String = ""

    /// Currently active plugin in dock search
    var dockActivePlugin: CommandBarPlugin? = nil

    /// Whether to show the plugin list in dock search
    var dockShowPluginList: Bool = false

    /// Plugin that matches current autocomplete in dock search
    var dockAutocompletePlugin: CommandBarPlugin? = nil

    // MARK: - Persistence Keys

    private static let stateKey = "FloatingDock.State"
    private static let positionKey = "FloatingDock.Position"

    // MARK: - Initialization

    init() {
        loadState()
        loadPosition()
    }

    // MARK: - State Persistence

    /// Save state to UserDefaults
    func saveState() {
        UserDefaults.standard.set(previewHeight, forKey: "\(Self.stateKey).previewHeight")
        UserDefaults.standard.set(previewWidth, forKey: "\(Self.stateKey).previewWidth")
        UserDefaults.standard.set(isVisible, forKey: "\(Self.stateKey).isVisible")
    }

    /// Load state from UserDefaults
    private func loadState() {
        if let savedHeight = UserDefaults.standard.object(forKey: "\(Self.stateKey).previewHeight")
            as? CGFloat
        {
            self.previewHeight = savedHeight
        }
        if let savedWidth = UserDefaults.standard.object(forKey: "\(Self.stateKey).previewWidth")
            as? CGFloat
        {
            self.previewWidth = savedWidth
        }
        if let savedVisible = UserDefaults.standard.object(forKey: "\(Self.stateKey).isVisible")
            as? Bool
        {
            self.isVisible = savedVisible
        }
    }

    // MARK: - Position Persistence

    /// Save position to UserDefaults
    func savePosition() {
        guard let position = dockPosition else {
            UserDefaults.standard.removeObject(forKey: Self.positionKey)
            return
        }

        let positionData = [
            "x": position.x,
            "y": position.y,
        ]
        UserDefaults.standard.set(positionData, forKey: Self.positionKey)
    }

    /// Load position from UserDefaults
    private func loadPosition() {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.positionKey),
            let x = dict["x"] as? CGFloat,
            let y = dict["y"] as? CGFloat
        else {
            self.dockPosition = nil
            return
        }
        self.dockPosition = NSPoint(x: x, y: y)
    }
}
