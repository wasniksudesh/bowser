// SplitCanvasView.swift - SwiftUI Bridge for Split Canvas
// Bowser - Swift 6.2
// NSViewControllerRepresentable wrapper for VS Code-style split editor

import SwiftUI
import AppKit
import Combine

// =============================================================================
// MARK: - Split Canvas View (SwiftUI Bridge)
// =============================================================================

/// SwiftUI view that wraps the NSSplitView-based split canvas.
/// This is the main entry point for the split editor in SwiftUI views.
///
/// Features:
/// - VS Code-style split panes with infinite nesting
/// - Drag-and-drop from sidebar to split views
/// - Smooth animations for drop indicators
/// - Fullscreen support with proper constraints
///
/// Usage:
/// ```swift
/// SplitCanvasView(browserState: browserState)
///     .frame(maxWidth: .infinity, maxHeight: .infinity)
/// ```
struct SplitCanvasView: NSViewControllerRepresentable {
    
    // MARK: - Properties
    
    /// Browser state for tab management
    @Bindable var browserState: BrowserState
    
    /// Whether the window is in fullscreen mode
    var isFullScreen: Bool = false
    
    // MARK: - NSViewControllerRepresentable
    
    func makeNSViewController(context: Context) -> SplitCanvasViewController {
        let layoutState = context.coordinator.layoutState
        
        // CRITICAL: Sync the layout state with the current active tab BEFORE creating the view controller
        // This ensures the pane gets the correct tab ID from the start
        if let activeTab = browserState.activeTab {
            print("[SplitCanvasView] makeNSViewController - syncing active tab: \(activeTab.id)")
            // Update the root pane's tab ID to match the actual active tab
            if case .pane(let paneId, _) = layoutState.root {
                layoutState.root = .pane(id: paneId, tabId: activeTab.id)
            }
            // Sync split tab IDs for sidebar highlighting
            browserState.splitTabIds = Set(layoutState.root.allTabIds)
        }
        
        let viewController = SplitCanvasViewController(layoutState: layoutState)
        
        viewController.browserStateAccessor = { [weak browserState] in
            browserState
        }
        
        // Capture coordinator weakly for the closure
        let coordinator = context.coordinator
        viewController.onLayoutChange = { newRoot in
            coordinator.handleLayoutChange(newRoot)
        }
        
        context.coordinator.viewController = viewController
        
        return viewController
    }
    
    func updateNSViewController(_ viewController: SplitCanvasViewController, context: Context) {
        // Sync active tab changes
        if let activeTab = browserState.activeTab {
            context.coordinator.syncActiveTab(activeTab.id)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(browserState: browserState)
    }
    
    // MARK: - Coordinator
    
    /// Coordinator manages state synchronization between SwiftUI and AppKit
    @MainActor
    final class Coordinator {
        
        // MARK: - Properties
        
        /// Browser state reference
        weak var browserState: BrowserState?
        
        /// Layout state for the split canvas
        let layoutState: SplitLayoutState
        
        /// Reference to the view controller
        weak var viewController: SplitCanvasViewController?
        
        /// Subscription storage
        private var cancellables = Set<AnyCancellable>()
        
        // MARK: - Initialization
        
        init(browserState: BrowserState) {
            self.browserState = browserState
            
            // Initialize layout state with current active tab
            let initialTabId = browserState.activeTab?.id ?? UUID()
            self.layoutState = SplitLayoutState(initialTabId: initialTabId)
            
            // Initialize split tab IDs with the initial tab
            browserState.splitTabIds = Set([initialTabId])
            
            setupBindings()
        }
        
        // MARK: - Bindings
        
        /// Setup reactive bindings
        private func setupBindings() {
            // Subscribe to tab close notifications
            NotificationCenter.default.publisher(for: .tabWillClose)
                .compactMap { $0.userInfo?["tabId"] as? UUID }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] tabId in
                    self?.handleTabClosed(tabId)
                }
                .store(in: &cancellables)
            
            // Subscribe to save split and show single tab notifications
            NotificationCenter.default.publisher(for: .saveSplitAndShowSingleTab)
                .compactMap { $0.userInfo?["newTabId"] as? UUID }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newTabId in
                    self?.handleSaveSplitAndShowSingleTab(newTabId: newTabId)
                }
                .store(in: &cancellables)
            
            // Subscribe to restore split group notifications
            NotificationCenter.default.publisher(for: .restoreSplitGroup)
                .compactMap { $0.userInfo?["group"] as? SplitGroup }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] group in
                    self?.handleRestoreSplitGroup(group)
                }
                .store(in: &cancellables)
            
            // Subscribe to exit split view notifications
            NotificationCenter.default.publisher(for: .exitSplitView)
                .compactMap { $0.userInfo?["tabId"] as? UUID }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] tabId in
                    self?.handleExitSplitView(tabId: tabId)
                }
                .store(in: &cancellables)
        }
        
        // MARK: - State Sync
        
        /// Sync the active tab with the split layout
        /// 
        /// Behavior:
        /// - If the selected tab is already in a pane: Just focus that pane
        /// - If split view is open and tab is NOT in split: Exit split view and show selected tab
        /// - If single view: Replace the content with the selected tab
        func syncActiveTab(_ tabId: UUID) {
            // Check how many tabs are currently in the split layout
            let currentTabsInSplit = layoutState.root.allTabIds
            let hasSplitView = currentTabsInSplit.count > 1
            
            // Find if this tab exists in the layout
            if let paneId = layoutState.root.findPane(tabId: tabId) {
                // Tab is already in a pane - just update the active pane
                // No need to update the view since it's already showing this tab
                layoutState.activePaneId = paneId
            } else if hasSplitView {
                // Split view is open and this tab is not in any pane
                // User clicked on a tab outside the split - exit split view and show selected tab
                print("[SplitCanvasCoordinator] Exiting split view to show tab \(tabId)")
                
                // Save the current split as a group before exiting (if not already saved)
                if browserState?.savedSplitGroups.contains(where: { Set($0.tabIds) == Set(currentTabsInSplit) }) != true {
                    let group = SplitGroup(rootNode: layoutState.root)
                    browserState?.saveSplitGroup(group)
                    print("[SplitCanvasCoordinator] Saved split group with \(currentTabsInSplit.count) tabs before switching")
                }
                
                // Reset to single view with the selected tab
                resetToSingleTab(tabId)
            } else {
                // Single view - update the pane to show this tab
                // This handles the case where the user selects a different tab from the sidebar
                if let activePaneId = layoutState.activePaneId {
                    // Update the root to show the new tab in the active pane
                    layoutState.root = layoutState.root.updateTabId(paneId: activePaneId, newTabId: tabId)
                    
                    // Tell the view controller to update the browser view
                    viewController?.updatePaneTab(paneId: activePaneId, tabId: tabId)
                } else {
                    // No active pane - update the first pane we find
                    if case .pane(let paneId, _) = layoutState.root {
                        layoutState.root = .pane(id: paneId, tabId: tabId)
                        layoutState.activePaneId = paneId
                        viewController?.updatePaneTab(paneId: paneId, tabId: tabId)
                    }
                }
            }
            
            // Sync split tab IDs with BrowserState for sidebar highlighting
            // Only update if the set actually changed to prevent unnecessary re-renders
            let newSplitTabIds = Set(layoutState.root.allTabIds)
            if browserState?.splitTabIds != newSplitTabIds {
                browserState?.splitTabIds = newSplitTabIds
            }
        }
        
        /// Handle layout change from AppKit
        func handleLayoutChange(_ newRoot: SplitNode) {
            // Layout was updated in AppKit, sync any needed state
            let tabIds = newRoot.allTabIds
            print("[SplitCanvasCoordinator] Layout changed: \(tabIds.count) tabs in split - IDs: \(tabIds)")
            
            // Update BrowserState with the current split tab IDs
            // Only update if the set actually changed to prevent sidebar flickering during resize
            let newSplitTabIds = Set(tabIds)
            if browserState?.splitTabIds != newSplitTabIds {
                browserState?.splitTabIds = newSplitTabIds
            }
            
            // Handle split group management based on tab count
            if tabIds.count >= 2 {
                // Update or create the split group
                browserState?.updateOrCreateSplitGroup(rootNode: newRoot)
            } else {
                // Only 1 or 0 tabs remaining - clear any split groups that overlap
                // and ensure we have valid state
                browserState?.clearInvalidSplitGroups()
            }
        }
        
        /// Handle tab close
        func handleTabClosed(_ tabId: UUID) {
            // Find and remove any pane displaying this tab
            if let paneId = layoutState.root.findPane(tabId: tabId) {
                viewController?.closePane(paneId)
            }
            
            // Remove this tab from any saved split groups
            browserState?.removeTabFromSplitGroups(tabId)
            
            // Also check if any split groups are still valid
            browserState?.clearInvalidSplitGroups()
        }
        
        /// Save the current split layout and switch to single tab view
        func handleSaveSplitAndShowSingleTab(newTabId: UUID) {
            let currentTabIds = layoutState.root.allTabIds
            guard currentTabIds.count > 1 else { return }
            
            // Create a split group with the full tree structure
            let group = SplitGroup(rootNode: layoutState.root)
            
            print("[SplitCanvasCoordinator] Saving split group with \(currentTabIds.count) tabs: \(currentTabIds)")
            
            // Save the group to BrowserState
            browserState?.saveSplitGroup(group)
            
            // Reset to single view with the new tab
            resetToSingleTab(newTabId)
        }
        

        
        /// Reset the layout to single tab view
        private func resetToSingleTab(_ tabId: UUID) {
            let paneId = UUID()
            layoutState.root = .pane(id: paneId, tabId: tabId)
            layoutState.activePaneId = paneId
            
            // Update the view controller
            viewController?.resetToSinglePane(paneId: paneId, tabId: tabId)
            
            // Update BrowserState
            browserState?.splitTabIds = Set([tabId])
            
            // Select the new tab
            if let browserState = browserState,
               let tab = browserState.tabs.first(where: { $0.id == tabId }) {
                browserState.selectTab(tab)
            }
            
            print("[SplitCanvasCoordinator] Reset to single tab: \(tabId)")
        }
        
        /// Restore a saved split group
        func handleRestoreSplitGroup(_ group: SplitGroup) {
            guard group.tabIds.count >= 2 else { return }
            
            // Save current split if it exists before restoring new one
            let currentTabsInSplit = layoutState.root.allTabIds
            if currentTabsInSplit.count > 1 {
                if browserState?.savedSplitGroups.contains(where: { Set($0.tabIds) == Set(currentTabsInSplit) }) != true {
                    let currentGroup = SplitGroup(rootNode: layoutState.root)
                    browserState?.saveSplitGroup(currentGroup)
                    print("[SplitCanvasCoordinator] Auto-saved current split before restoring another")
                }
            }
            
            print("[SplitCanvasCoordinator] Restoring split group with \(group.tabIds.count) tabs")
            
            // Use the stored rootNode directly - preserves exact structure and positions
            let newRoot = group.rootNode
            layoutState.root = newRoot
            
            // Set active pane to the first one
            if let firstTabId = group.tabIds.first,
               let firstPaneId = newRoot.findPane(tabId: firstTabId) {
                layoutState.activePaneId = firstPaneId
            }
            
            // Update the view controller
            viewController?.restoreSplitLayout(root: newRoot)
            
            // Update BrowserState
            browserState?.splitTabIds = Set(group.tabIds)
            
            // Select the first tab in the group
            if let browserState = browserState,
               let firstTabId = group.tabIds.first,
               let tab = browserState.tabs.first(where: { $0.id == firstTabId }) {
                browserState.selectTab(tab)
            }
        }
        
        /// Exit split view and show a single tab (without saving)
        /// Removes the tab from any saved split groups before showing it alone
        func handleExitSplitView(tabId: UUID) {
            print("[SplitCanvasCoordinator] Exiting split view to show tab: \(tabId)")
            
            // Remove this tab from any saved split groups
            // This ensures the tab is no longer part of the split group in the sidebar
            browserState?.removeTabFromSplitGroups(tabId)
            
            resetToSingleTab(tabId)
        }
    }
}

// =============================================================================
// MARK: - Floating Split Canvas View
// =============================================================================

/// Arc-style floating card wrapper for the split canvas.
/// Adds the floating card visual treatment (padding, corners, shadow).
struct FloatingSplitCanvasView: View {
    
    @Bindable var browserState: BrowserState
    
    /// Whether window is in fullscreen mode
    var isFullScreen: Bool
    
    /// Card corner radius - 0 in fullscreen
    private var cardCornerRadius: CGFloat {
        isFullScreen ? 0 : ArcTheme.cardCornerRadius
    }
    
    /// Padding between card and window edges - 0 in fullscreen
    private var cardPadding: CGFloat {
        isFullScreen ? 0 : ArcTheme.cardPadding
    }
    
    /// Shadow color - clear in fullscreen
    private var shadowColor: Color {
        isFullScreen ? Color.clear : ArcTheme.primaryShadow.color
    }
    
    /// Shadow radius - 0 in fullscreen
    private var shadowRadius: CGFloat {
        isFullScreen ? 0 : ArcTheme.primaryShadow.radius
    }
    
    /// Shadow Y offset - 0 in fullscreen
    private var shadowY: CGFloat {
        isFullScreen ? 0 : ArcTheme.primaryShadow.y
    }
    
    var body: some View {
        Group {
            if browserState.activeTab != nil {
                SplitCanvasView(browserState: browserState, isFullScreen: isFullScreen)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyTabView
            }
        }
        .background(CardBackgroundView())
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        .shadow(
            color: isFullScreen ? Color.clear : ArcTheme.secondaryShadow.color,
            radius: isFullScreen ? 0 : ArcTheme.secondaryShadow.radius,
            x: 0,
            y: isFullScreen ? 0 : ArcTheme.secondaryShadow.y
        )
        .padding(.top, cardPadding)
        .padding(.leading, cardPadding)
        .padding(.trailing, cardPadding)
        .padding(.bottom, cardPadding)
        .background(Color.clear)
        .ignoresSafeArea(.all, edges: isFullScreen ? .all : [.top, .bottom])
    }
    
    /// Fallback view when no tab is selected
    private var emptyTabView: some View {
        Text("No tab selected")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundColor(.secondary)
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct SplitCanvasView_Previews: PreviewProvider {
    static var previews: some View {
        FloatingSplitCanvasView(
            browserState: BrowserState(),
            isFullScreen: false
        )
        .frame(width: 1000, height: 700)
        .background(Color.gray.opacity(0.2))
    }
}
#endif
