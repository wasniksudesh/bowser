// SidebarHeaderView.swift - Arc-Style Sidebar Header with Traffic Light Integration
// SwiftUI 6.2 with synchronized layout using TrafficLightLayoutConfig
// Implements the reference sketch: Traffic Lights → Sidebar Toggle → Navigation Options

import SwiftUI

// =============================================================================
// MARK: - Sidebar Header View
// =============================================================================

/// Arc-style sidebar header positioned at the absolute top of the sidebar.
///
/// This view implements the layout shown in the reference sketch:
/// ```
/// ┌─────────────────────────────────────────────┐
/// │ [●][●][●]  [≡]              [←][→][↻]      │
/// │  Traffic   Toggle           Navigation      │
/// │  Lights                     Options         │
/// └─────────────────────────────────────────────┘
/// ```
///
/// ## Synchronization with AppKit Traffic Lights
/// The key to this design is that the **SwiftUI padding must exactly match** the space
/// occupied by the AppKit traffic light buttons. This is achieved through the
/// `TrafficLightLayoutConfig`, which serves as the **single source of truth**:
///
/// 1. AppKit uses `config.xOffset`, `config.yOffset` to position NSButtons
/// 2. SwiftUI uses `config.reservedWidth`, `config.reservedHeight` for spacers
/// 3. Both derive from identical source values = guaranteed synchronization
///
/// ## Architecture (SOLID Principles)
/// - **Single Responsibility**: Only handles sidebar header layout
/// - **Dependency Inversion**: Receives layout config from environment/parameter
/// - **Open/Closed**: New button styles can be added without modifying core layout
struct SidebarHeaderView: View {

    // MARK: - Properties

    /// Browser state for navigation actions and sidebar state
    var browserState: BrowserState

    /// Layout configuration for traffic light synchronization
    /// Defaults to Arc browser configuration if not provided via environment
    var layoutConfig: TrafficLightLayoutConfig = .arcBrowser

    /// Binding to control sidebar visibility
    @Binding var isSidebarCollapsed: Bool

    /// Track fullscreen state for layout adjustments
    @State private var isFullScreen: Bool = false

    // MARK: - Environment

    @Environment(\.trafficLightLayoutConfig) private var environmentLayoutConfig

    /// Effective layout config (parameter takes precedence over environment)
    private var effectiveLayoutConfig: TrafficLightLayoutConfig {
        // Use parameter if explicitly set, otherwise fall back to environment
        layoutConfig
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // MARK: Traffic Light Reserved Space
            // This spacer occupies exactly the space needed for AppKit traffic lights
            trafficLightSpacer

            // MARK: Sidebar Toggle Button
            sidebarToggleButton

            // MARK: Panel Mode Toggle (Tab/Plan)
            panelModeToggle

            Spacer()

            // MARK: Navigation Options (Right Side)
            navigationButtonsRow
        }
        .frame(height: effectiveLayoutConfig.reservedHeight)
        .frame(maxWidth: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .framelessWindowDidEnterFullScreen)) {
            _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .framelessWindowDidExitFullScreen)) {
            _ in
            isFullScreen = false
        }
    }

    // MARK: - Traffic Light Spacer

    /// Invisible spacer that reserves exactly the width needed for traffic light buttons.
    ///
    /// This spacer ensures SwiftUI content doesn't overlap the AppKit traffic lights.
    /// The width is computed from `TrafficLightLayoutConfig` to guarantee synchronization.
    private var trafficLightSpacer: some View {
        Color.clear
            .frame(
                width: effectiveLayoutConfig.reservedWidth
                    - effectiveLayoutConfig.sidebarToggleSpacing)
    }

    // MARK: - Sidebar Toggle Button

    /// Button to collapse/expand the sidebar.
    ///
    /// Positioned immediately after the traffic lights, matching the reference sketch.
    private var sidebarToggleButton: some View {
        Button(action: toggleSidebar) {
            Image(systemName: isSidebarCollapsed ? "sidebar.left" : "sidebar.leading")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(
                    width: effectiveLayoutConfig.sidebarToggleSize,
                    height: effectiveLayoutConfig.sidebarToggleSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isSidebarCollapsed ? "Show Sidebar" : "Hide Sidebar")
        .opacity(0.7)
        .padding(.leading, effectiveLayoutConfig.sidebarToggleSpacing)
    }
    
    // MARK: - Panel Mode Toggle
    
    /// Segmented control to switch between Tab, Plan, and Agent modes
    ///
    /// Positioned after the sidebar toggle button
    private var panelModeToggle: some View {
        HStack(spacing: 2) {
            // Tab Mode Button
            Button(action: { browserState.currentPanelMode = .tab }) {
                Text("Tab")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(browserState.currentPanelMode == .tab ? .primary : .secondary)
                    .frame(width: 35, height: 20)
                    .background(
                        browserState.currentPanelMode == .tab
                            ? Color(nsColor: .controlBackgroundColor)
                            : Color.clear
                    )
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            
            // Plan Mode Button
            Button(action: { browserState.currentPanelMode = .plan }) {
                Text("Plan")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(browserState.currentPanelMode == .plan ? .primary : .secondary)
                    .frame(width: 35, height: 20)
                    .background(
                        browserState.currentPanelMode == .plan
                            ? Color(nsColor: .controlBackgroundColor)
                            : Color.clear
                    )
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            
            // Agent Mode Button
            Button(action: { browserState.currentPanelMode = .agent }) {
                Image(systemName: "cpu")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(browserState.currentPanelMode == .agent ? .primary : .secondary)
                    .frame(width: 35, height: 20)
                    .background(
                        browserState.currentPanelMode == .agent
                            ? Color(nsColor: .controlBackgroundColor)
                            : Color.clear
                    )
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Agent Mode")
        }
        .padding(2)
        .background(Color(nsColor: .controlColor).opacity(0.5))
        .cornerRadius(6)
        .padding(.leading, 8)
    }

    // MARK: - Navigation Buttons

    /// Navigation buttons row (Stack Toggle, Back, Forward, Reload/Stop).
    ///
    /// Positioned at the right side of the header, matching the reference sketch.
    private var navigationButtonsRow: some View {
        HStack(spacing: 4) {
            // Stack Mode Toggle Button
            NavigationButton(
                systemName: isStackModeEnabled ? "square.stack.3d.up.fill" : "square.stack.3d.up",
                action: toggleStackMode,
                isEnabled: !isInSplitMode,
                helpText: isStackModeEnabled ? "Disable Stack Mode" : "Enable Stack Mode"
            )

            // Back Button
            NavigationButton(
                systemName: "chevron.left",
                action: goBack,
                isEnabled: browserState.canGoBack,
                helpText: "Back"
            )

            // Forward Button
            NavigationButton(
                systemName: "chevron.right",
                action: goForward,
                isEnabled: browserState.canGoForward,
                helpText: "Forward"
            )

            // Reload/Stop Button
            NavigationButton(
                systemName: browserState.isLoading ? "xmark" : "arrow.clockwise",
                action: reloadOrStop,
                isEnabled: true,
                helpText: browserState.isLoading ? "Stop" : "Reload"
            )
        }
        .padding(.trailing, effectiveLayoutConfig.trailingPadding)
    }

    // MARK: - Computed Properties

    private var isInSplitMode: Bool {
        browserState.splitTabIds.count > 1
    }

    private var isStackModeEnabled: Bool {
        browserState.activeTab?.stackModeEnabled ?? false
    }

    // MARK: - Actions

    private func toggleSidebar() {
        // Toggle the binding - animation is handled by the parent's Binding setter
        isSidebarCollapsed.toggle()

        // Notify traffic light coordinator of sidebar state change
        NotificationCenter.default.post(
            name: .sidebarVisibilityDidChange,
            object: nil,
            userInfo: ["isCollapsed": isSidebarCollapsed]
        )
    }

    private func toggleStackMode() {
        guard var tab = browserState.activeTab else { return }

        // Cannot enable stack mode if in split view
        if !tab.stackModeEnabled && isInSplitMode {
            print("[SidebarHeaderView] Cannot enable stack mode - tab is in split view")
            return
        }

        let newStackMode = !tab.stackModeEnabled

        if newStackMode {
            // Enabling stack mode: convert current page to first page in stack
            // The page will get a new browserId, and we'll need to recreate the browser
            let initialPage = Page(
                url: tab.url,
                title: tab.title,
                favicon: tab.favicon,
                icon: tab.icon,
                isLoading: tab.isLoading,
                canGoBack: tab.canGoBack,
                canGoForward: tab.canGoForward
            )

            // Close the old tab-level browser
            BrowserManager.shared.closeBrowser(for: tab.id)

            tab.pages = [initialPage]
            tab.activePageIndex = 0
            tab.stackModeEnabled = true

            // Update tab in manager
            browserState.tabManager.replaceTab(id: tab.id, with: tab)

            // The new page browser will be created lazily by BrowserCanvas when it renders
        } else {
            // Disabling stack mode: keep only active page, discard others
            // Close all page browsers
            let pageIds = tab.pages.map { $0.browserId }
            BrowserManager.shared.closeAllBrowsersForPages(pageIds: pageIds)

            if let activePage = tab.activePage {
                // Update pane with active page's data
                tab.url = activePage.url
                tab.title = activePage.title
            }
            tab.pages = []
            tab.activePageIndex = 0
            tab.stackModeEnabled = false

            // Update tab in manager
            browserState.tabManager.replaceTab(id: tab.id, with: tab)

            // Recreate the tab-level browser to apply new gesture settings
            BrowserManager.shared.recreateBrowser(for: tab.id, delegate: nil)
        }
    }

    private func goBack() {
        guard let activeTab = browserState.activeTab else { return }

        // In stack mode, navigate the active page's browser
        if activeTab.stackModeEnabled, let activePage = activeTab.activePage {
            BrowserManager.shared.goBack(pageId: activePage.browserId)
        } else {
            // In non-stack mode, use the tab's browser (pane mode)
            BrowserManager.shared.goBack(pageId: activeTab.id)
        }
    }

    private func goForward() {
        guard let activeTab = browserState.activeTab else { return }

        // In stack mode, navigate the active page's browser
        if activeTab.stackModeEnabled, let activePage = activeTab.activePage {
            BrowserManager.shared.goForward(pageId: activePage.browserId)
        } else {
            // In non-stack mode, use the tab's browser (pane mode)
            BrowserManager.shared.goForward(pageId: activeTab.id)
        }
    }

    private func reloadOrStop() {
        guard let activeTab = browserState.activeTab else { return }

        // In stack mode, operate on the active page's browser
        if activeTab.stackModeEnabled, let activePage = activeTab.activePage {
            if browserState.isLoading {
                BrowserManager.shared.stopLoading(pageId: activePage.browserId)
            } else {
                BrowserManager.shared.reload(pageId: activePage.browserId)
            }
        } else {
            // In non-stack mode, use the tab's browser (pane mode)
            if browserState.isLoading {
                BrowserManager.shared.stopLoading(pageId: activeTab.id)
            } else {
                BrowserManager.shared.reload(pageId: activeTab.id)
            }
        }
    }
}

// =============================================================================
// MARK: - Navigation Button Component
// =============================================================================

/// Reusable navigation button with consistent styling.
///
/// Extracted as a separate component following Single Responsibility Principle.
private struct NavigationButton: View {
    let systemName: String
    let action: () -> Void
    let isEnabled: Bool
    let helpText: String

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(helpText)
        .opacity(isEnabled ? 1.0 : 0.5)
    }
}

// =============================================================================
// MARK: - Convenience Initializers
// =============================================================================

extension SidebarHeaderView {

    /// Initialize with browser state and sidebar binding only.
    ///
    /// Uses default Arc browser layout configuration.
    init(browserState: BrowserState, isSidebarCollapsed: Binding<Bool>) {
        self.browserState = browserState
        self._isSidebarCollapsed = isSidebarCollapsed
        self.layoutConfig = .arcBrowser
    }
}

// =============================================================================
// MARK: - Notification Names
// =============================================================================

extension Notification.Name {
    /// Posted when sidebar visibility changes (collapsed/expanded)
    static let sidebarVisibilityDidChange = Notification.Name("Bowser.sidebarVisibilityDidChange")
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
    struct SidebarHeaderView_Previews: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 0) {
                // Simulated traffic light area overlay
                ZStack(alignment: .topLeading) {
                    // Header view
                    SidebarHeaderView(
                        browserState: BrowserState(),
                        isSidebarCollapsed: .constant(false)
                    )
                    .background(Color.gray.opacity(0.2))

                    // Traffic light simulation (for preview only)
                    HStack(spacing: 8) {
                        Circle().fill(.red).frame(width: 14, height: 14)
                        Circle().fill(.yellow).frame(width: 14, height: 14)
                        Circle().fill(.green).frame(width: 14, height: 14)
                    }
                    .padding(.leading, 20)
                    .padding(.top, 11)
                }

                Spacer()
            }
            .frame(width: 280, height: 200)
            .preferredColorScheme(.dark)
        }
    }
#endif
