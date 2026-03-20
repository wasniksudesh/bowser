// NavigationNotifications.swift - Browser Navigation Notification Names
// Extracted from AddressBar.swift during codebase cleanup
// Centralized notification definitions for browser navigation events

import Foundation

// =============================================================================
// MARK: - Navigation Notification Names
// =============================================================================

extension Notification.Name {
    /// Navigate to a URL (userInfo: ["url": URL])
    static let navigateToURL = Notification.Name("navigateToURL")

    /// Reload the current page
    static let reloadPage = Notification.Name("reloadPage")

    /// Stop loading the current page
    static let stopLoading = Notification.Name("stopLoading")

    /// Navigate back in history
    static let goBack = Notification.Name("goBack")

    /// Navigate forward in history
    static let goForward = Notification.Name("goForward")

    /// Open the command bar modal
    static let openCommandBar = Notification.Name("openCommandBar")

    /// Focus the address bar (opens command bar)
    static let focusAddressBar = Notification.Name("focusAddressBar")

    /// Create a new tab (opens command bar)
    static let newTab = Notification.Name("newTab")

    /// Capture a snapshot of the current tab for preview
    static let captureTabSnapshot = Notification.Name("captureTabSnapshot")

    /// Tab is about to be closed (userInfo: ["tabId": UUID])
    static let tabWillClose = Notification.Name("tabWillClose")

    /// Window entered fullscreen mode
    static let windowDidEnterFullScreen = Notification.Name("windowDidEnterFullScreen")

    /// Window exited fullscreen mode
    static let windowDidExitFullScreen = Notification.Name("windowDidExitFullScreen")

    /// Save current split layout and switch to single tab view
    /// userInfo: ["newTabId": UUID] - the new tab to show in single view
    static let saveSplitAndShowSingleTab = Notification.Name("saveSplitAndShowSingleTab")

    /// Restore a saved split group
    /// userInfo: ["group": SplitGroup] - the split group to restore
    static let restoreSplitGroup = Notification.Name("restoreSplitGroup")

    /// Exit split view and show single tab (without saving)
    /// userInfo: ["tabId": UUID] - the tab to show in single view
    static let exitSplitView = Notification.Name("exitSplitView")

    /// Zoom in (CMD+)
    static let zoomIn = Notification.Name("zoomIn")

    /// Zoom out (CMD-)
    static let zoomOut = Notification.Name("zoomOut")

    /// Reset zoom to 100% (CMD0)
    static let resetZoom = Notification.Name("resetZoom")

    /// Stack gesture changed (userInfo: ["tabId": UUID, "translation": CGFloat, "velocity": CGFloat])
    static let stackGestureChanged = Notification.Name("stackGestureChanged")

    /// Stack gesture ended (userInfo: ["tabId": UUID, "translation": CGFloat, "velocity": CGFloat])
    static let stackGestureEnded = Notification.Name("stackGestureEnded")

    /// Show Settings Window
    static let showSettings = Notification.Name("showSettings")
}
