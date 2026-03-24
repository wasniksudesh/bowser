// AppNavigationState.swift - Top-level navigation state for homescreen/browser switching

import Foundation
import Observation

// =============================================================================
// MARK: - App Navigation State
// =============================================================================

/// Controls which top-level screen the app is showing: the homescreen desktop
/// or the browser interface for a specific folder.
@Observable
@MainActor
final class AppNavigationState {

    // MARK: - Screen Enum

    enum Screen: Equatable {
        case homescreen
        case browser(folderId: UUID)

        static func == (lhs: Screen, rhs: Screen) -> Bool {
            switch (lhs, rhs) {
            case (.homescreen, .homescreen):
                return true
            case (.browser(let a), .browser(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    // MARK: - State

    var currentScreen: Screen = .homescreen

    // MARK: - Computed Properties

    var isShowingHomescreen: Bool {
        if case .homescreen = currentScreen { return true }
        return false
    }

    var activeFolderId: UUID? {
        if case .browser(let id) = currentScreen { return id }
        return nil
    }

    // MARK: - Actions

    func goHome() {
        currentScreen = .homescreen
    }

    func openFolder(_ folderId: UUID) {
        currentScreen = .browser(folderId: folderId)
    }
}
