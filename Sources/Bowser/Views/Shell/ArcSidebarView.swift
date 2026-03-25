// ArcSidebarView.swift - Arc-Style Complete Sidebar
// Extracted from AppShellView for modularity and reuse

import AppKit
import SwiftUI

// =============================================================================
// MARK: - Sidebar Item Model (Unified Ordering)
// =============================================================================

/// Represents an item in the sidebar tab list
/// Enables unified ordering of split groups and regular tabs
enum SidebarItem: Identifiable {
    case splitGroup(SplitGroup, isActive: Bool)
    case tab(Tab)

    var id: String {
        switch self {
        case .splitGroup(let group, _):
            return "split-\(group.id)"
        case .tab(let tab):
            return "tab-\(tab.id)"
        }
    }

    /// Sorting key based on the first tab's position in the tabs array
    func sortKey(allTabs: [Tab]) -> Int {
        switch self {
        case .splitGroup(let group, _):
            // Find the earliest tab position from this group
            let positions = group.tabIds.compactMap { tabId in
                allTabs.firstIndex { $0.id == tabId }
            }
            return positions.min() ?? Int.max
        case .tab(let tab):
            return allTabs.firstIndex { $0.id == tab.id } ?? Int.max
        }
    }
}

// =============================================================================
// MARK: - Arc Sidebar View
// =============================================================================

/// Complete Arc-style sidebar containing all navigation elements.
/// This view replaces the original SidebarView + top AddressBar combination.
///
/// ## Section Layout (top to bottom)
    /// 1. **Sidebar Header** - Traffic lights space + Sidebar toggle + Navigation buttons
    /// 2. **Sidebar URL Bar** - Compact address/search field
    /// 3. **Pinned Tabs** - Horizontal strip of pinned tabs
    /// 4. **Tab List** - Vertical list of open tabs
    /// 5. **AI Controls** - AI assistant status/actions
    /// 6. **Tools + Home + History** - Bottom bar buttons
///
/// ## Traffic Light Synchronization
/// The `SidebarHeaderView` uses `TrafficLightLayoutConfig` to reserve exactly the space
/// needed for the AppKit traffic lights. This config is the **single source of truth**
/// shared between AppKit (button positioning) and SwiftUI (spacer sizing).
///
/// ## Fullscreen Behavior
/// In fullscreen mode, the header adjusts automatically based on the layout config.
struct ArcSidebarView: View {

    @Bindable var browserState: BrowserState

    /// Navigation state for transitioning back to homescreen
    @Bindable var appNav: AppNavigationState

    /// Binding to parent's showCommandBar state
    @Binding var showCommandBar: Bool

    /// Whether window is in fullscreen mode
    var isFullScreen: Bool

    /// Binding to control sidebar visibility from parent NavigationSplitView
    @Binding var isSidebarCollapsed: Bool

    /// Layout configuration for traffic light synchronization
    /// This is the **single source of truth** shared with FramelessWindow
    private var layoutConfig: TrafficLightLayoutConfig {
        isFullScreen ? .fullscreen : .arcBrowser
    }

    /// Namespace for address bar matched geometry transitions
    @Namespace private var addressBarNamespace

    /// Tab being dragged for reordering
    @State private var draggedTab: Tab?

    /// Whether the History panel is currently shown
    @State private var showingHistory = false

    /// Whether the Tools panel is expanded
    @State private var showingTools = false

    // MARK: - Cached Sidebar State (Performance Optimization)

    /// Cached sidebar items to avoid expensive recomputation on every render
    /// Invalidated when tabs, split groups, or split tab IDs change
    @State private var cachedUnifiedItems: [SidebarItem] = []
    @State private var cachedFilteredTabs: [Tab] = []
    @State private var lastCacheKey: String = ""

    /// Generate a cache key from the current state
    /// PERFORMANCE: Uses a checksum approach rather than building strings for each tab
    private var cacheKey: String {
        let tabCount = browserState.tabs.count
        let splitCount = browserState.splitTabIds.count
        let groupCount = browserState.savedSplitGroups.count
        let firstTabId = browserState.tabs.first?.id.uuidString ?? "none"
        let lastTabId = browserState.tabs.last?.id.uuidString ?? "none"
        // Include parent structure checksum for tree hierarchy changes
        let parentChecksum = browserState.tabs.reduce(0) { $0 &+ ($1.parentTabId?.hashValue ?? 0) }
        return
            "\(tabCount)-\(splitCount)-\(groupCount)-\(firstTabId)-\(lastTabId)-\(parentChecksum)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // ═══════════════════════════════════════════════════════════════
            // NOTE: No local vibrancy background here!
            // The sidebar is intentionally transparent so the unified
            // backdrop (from AppShellView) shows through seamlessly.
            // This creates the "single continuous surface" effect.
            // ═══════════════════════════════════════════════════════════════

            // ───────────────────────────────────────────────────────────────
            // Sidebar Header (Traffic Lights + Toggle + Navigation)
            // Uses TrafficLightLayoutConfig for synchronized positioning.
            // The header reserves exactly the space needed for AppKit
            // traffic lights to prevent overlap.
            // ───────────────────────────────────────────────────────────────
            SidebarHeaderView(
                browserState: browserState,
                layoutConfig: layoutConfig,
                isSidebarCollapsed: $isSidebarCollapsed
            )

            // ───────────────────────────────────────────────────────────────
            // Sidebar URL Bar (Arc-style compact address bar)
            // ───────────────────────────────────────────────────────────────
            sidebarURLBarSection

            // ───────────────────────────────────────────────────────────────
            // Pinned Tabs
            // ───────────────────────────────────────────────────────────────
            pinnedTabsSection

            // ───────────────────────────────────────────────────────────────
            // Panel Content (Tab List, Plan Mode, Agent Mode, or History)
            // Switches based on browserState.currentPanelMode or showingHistory
            // ───────────────────────────────────────────────────────────────
            if showingHistory {
                HistoryView(browserState: browserState)
            } else {
                switch browserState.currentPanelMode {
                case .tab:
                    tabListSection
                case .plan:
                    PlanModeView(browserState: browserState)
                case .agent:
                    AgentSessionListView(browserState: browserState)
                }
            }

            Spacer(minLength: 0)

            // ───────────────────────────────────────────────────────────
            // Bottom Bar: Tools (full width) + Home | History
            // ───────────────────────────────────────────────────────────
            VStack(spacing: 4) {
                toolsSection
                HStack(spacing: 4) {
                    homeButton
                    historyButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        // ───────────────────────────────────────────────────────────────────
        // Transparent Sidebar Container
        // Force the sidebar to have no background so the unified backdrop
        // shows through. This is critical for the seamless surface effect.
        // ───────────────────────────────────────────────────────────────────
        .frame(minWidth: 220)
        .background(Color.clear)
        // CRITICAL: Extend sidebar content to the top edge of the window
        // This allows SidebarHeaderView to position where traffic lights are
        .ignoresSafeArea(.container, edges: .top)
        // Inject the layout config into the environment for child views
        .trafficLightLayoutConfig(layoutConfig)
    }

    // MARK: - Present Command Bar

    private func presentCommandBar() {
        NotificationCenter.default.post(name: .focusAddressBar, object: nil)
    }

    // MARK: - Sidebar URL Bar Section

    private var sidebarURLBarSection: some View {
        VStack(spacing: 8) {
            if !showCommandBar {
                SidebarURLBar(
                    browserState: browserState,
                    namespace: addressBarNamespace,
                    onTap: presentCommandBar
                )
                .matchedGeometryEffect(id: "urlBar", in: addressBarNamespace)
            } else {
                // Placeholder maintains layout during modal animation
                Color.clear
                    .frame(height: 36)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Pinned Tabs Section

    private var pinnedTabsSection: some View {
        let pinnedTabs = browserState.tabManager.pinnedTabs

        return Group {
            if !pinnedTabs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pinned")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .padding(.horizontal, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(pinnedTabs) { tab in
                                PinnedTabView(
                                    tab: tab,
                                    isActive: browserState.activeTab?.id == tab.id,
                                    onSelect: { browserState.selectTab(tab) }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Tab List Section

    private var tabListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // "Today" header (Arc groups tabs by time) with '+' button
            HStack {
                Text("Today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                Text("\(browserState.tabManager.unpinnedTabs.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)

                // ═══════════════════════════════════════════════════════════
                // New Tab Button ('+')
                // Opens Command Bar instead of immediately creating empty tab
                // ═══════════════════════════════════════════════════════════
                Button {
                    presentCommandBar()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Tab (⌘T)")
            }
            .padding(.horizontal, 4)

            // Tab list
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    // ═══════════════════════════════════════════════════════
                    // Unified Tab List - Maintains Original Order
                    // Split groups and regular tabs are interleaved based on
                    // the position of their first tab in the tabs array
                    // ═══════════════════════════════════════════════════════
                    ForEach(unifiedSidebarItems) { item in
                        switch item {
                        case .splitGroup(let splitGroup, let isActive):
                            if isActive {
                                // This is the currently active split - show as ActiveSplitGroupView
                                ActiveSplitGroupView(
                                    tabIds: browserState.splitTabIds,
                                    tabs: browserState.tabs,
                                    activeTabId: browserState.activeTab?.id
                                )
                            } else {
                                // This is a saved (inactive) split - show as SplitGroupRowView
                                SplitGroupRowView(
                                    group: splitGroup,
                                    tabs: browserState.tabs,
                                    onRestore: { browserState.restoreSplitGroup(splitGroup) },
                                    onDismiss: { browserState.removeSplitGroup(splitGroup) }
                                )
                            }
                        case .tab(let tab):
                            if browserState.splitTabIds.count <= 1 {
                                // Single-view mode: render as tree node
                                // (TabTreeView handles tree structure internally)
                            } else {
                                // Split-view mode: show flat row
                                TabRowView(
                                    tab: tab,
                                    isActive: browserState.activeTab?.id == tab.id,
                                    isInSplit: browserState.splitTabIds.contains(tab.id),
                                    onSelect: {
                                        print("[ArcSidebarView] onSelect")
                                        browserState.selectTab(tab)
                                    },
                                    onClose: { browserState.closeTab(tab) },
                                    onPin: { browserState.togglePin(tab) },
                                    onOpenChildTab: {
                                        let newUrl = URL(string: "https://www.google.com")!
                                        _ = browserState.tabManager.createChildTab(
                                            url: newUrl,
                                            title: "New Tab",
                                            parentId: tab.id
                                        )
                                    }
                                )
                                .draggableTab(tabId: tab.id, draggedTab: $draggedTab, tab: tab)
                                .onDrop(
                                    of: [.text],
                                    delegate: TabDropDelegate(
                                        tab: tab,
                                        draggedTab: $draggedTab,
                                        browserState: browserState
                                    ))
                            }
                        }
                    }

                    // ═══════════════════════════════════════════════════════
                    // Tree View for Single-View Mode
                    // Only shown when not in split view, renders the tree structure
                    // ═══════════════════════════════════════════════════════
                    if browserState.splitTabIds.count <= 1 {
                        TabTreeView(
                            browserState: browserState,
                            tabs: filteredUnpinnedTabs,
                            onSelect: { browserState.selectTab($0) },
                            onClose: { browserState.closeTab($0) },
                            onPin: { browserState.togglePin($0) },
                            onOpenChildTab: { parentTab in
                                let newUrl = URL(string: "https://www.google.com")!
                                _ = browserState.tabManager.createChildTab(
                                    url: newUrl,
                                    title: "New Tab",
                                    parentId: parentTab.id
                                )
                            }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .task {
            // Initial cache population
            updateCacheIfNeeded()
        }
        .onChange(of: cacheKey) { _, _ in
            updateCacheIfNeeded()
        }
    }

    // MARK: - Cache Management

    /// Update cached values if the cache key has changed
    private func updateCacheIfNeeded() {
        let key = cacheKey
        guard key != lastCacheKey else { return }
        lastCacheKey = key
        cachedUnifiedItems = computeUnifiedSidebarItems()
        cachedFilteredTabs = computeFilteredUnpinnedTabs()
    }

    /// Unified sidebar items - uses cached value for performance
    private var unifiedSidebarItems: [SidebarItem] {
        // Return cached if available, otherwise compute directly
        if !cachedUnifiedItems.isEmpty || lastCacheKey == cacheKey {
            return cachedUnifiedItems
        }
        return computeUnifiedSidebarItems()
    }

    /// Compute unified sidebar items - split groups and tabs in original order
    private func computeUnifiedSidebarItems() -> [SidebarItem] {
        var items: [SidebarItem] = []
        let allTabs = browserState.tabManager.unpinnedTabs
        let currentSplitTabIds = browserState.splitTabIds
        let splitGroupTabIds = Set(browserState.savedSplitGroups.flatMap { $0.tabIds })

        // Add split groups as items
        for splitGroup in browserState.savedSplitGroups
        where splitGroup.isValid(tabs: browserState.tabs) {
            let isCurrentlyActive =
                currentSplitTabIds.count > 1 && Set(splitGroup.tabIds) == currentSplitTabIds
            items.append(.splitGroup(splitGroup, isActive: isCurrentlyActive))
        }

        // In split-view mode, add non-split tabs as separate items
        if currentSplitTabIds.count > 1 {
            for tab in allTabs {
                // Skip tabs in active split or saved groups
                if currentSplitTabIds.contains(tab.id) { continue }
                if splitGroupTabIds.contains(tab.id) { continue }
                items.append(.tab(tab))
            }
        }

        // Sort items by their position in the original tab order
        items.sort { $0.sortKey(allTabs: allTabs) < $1.sortKey(allTabs: allTabs) }

        return items
    }

    /// Tabs that are not in the current split view or saved split group - uses cached value
    private var filteredUnpinnedTabs: [Tab] {
        // Return cached if available
        if !cachedFilteredTabs.isEmpty || lastCacheKey == cacheKey {
            return cachedFilteredTabs
        }
        return computeFilteredUnpinnedTabs()
    }

    /// Compute filtered unpinned tabs
    private func computeFilteredUnpinnedTabs() -> [Tab] {
        let splitGroupTabIds = Set(browserState.savedSplitGroups.flatMap { $0.tabIds })
        let currentSplitTabIds = browserState.splitTabIds

        return browserState.tabManager.unpinnedTabs.filter { tab in
            // Hide tabs that are in the active split view (shown in ActiveSplitGroupView)
            if currentSplitTabIds.count > 1 && currentSplitTabIds.contains(tab.id) {
                return false
            }
            // Hide tabs that are in the saved split group (shown in SplitGroupRowView)
            if splitGroupTabIds.contains(tab.id) {
                return false
            }
            return true
        }
    }

    // MARK: - Sidebar Bottom Button Helper

    /// Uniform sidebar bottom button used for Home and History.
    /// Both share the same height and layout so they line up evenly.
    private func sidebarBottomButton(
        icon: String,
        label: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? .primary : .secondary)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(isActive ? 0.07 : 0.03))
        )
    }

    // MARK: - Home Button

    private var homeButton: some View {
        sidebarBottomButton(icon: "house.fill", label: "Home") {
            showingHistory = false
            browserState.saveCurrentFolder()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                appNav.goHome()
            }
        }
        .help("Go to Homescreen")
    }

    // MARK: - History Button

    private var historyButton: some View {
        sidebarBottomButton(
            icon: showingHistory ? "clock.fill" : "clock",
            label: "History",
            isActive: showingHistory
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingHistory.toggle()
            }
        }
        .help("Browsing History")
    }

    // MARK: - Tools Section

    private var toolsSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingTools.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(showingTools ? .primary : .secondary)
                    Text("Tools")
                        .font(.system(size: 12))
                        .foregroundStyle(showingTools ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: showingTools ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showingTools {
                toolsGrid
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(showingTools ? 0.07 : 0.03))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                showingTools = hovering
            }
        }
    }

    // MARK: - Tools Grid

    private var toolsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
        ]

        return LazyVGrid(columns: columns, spacing: 6) {
            toolGridItem(icon: "arrow.down.circle", label: "Downloads") { }
            toolGridItem(icon: "camera", label: "Snapshot") {
                browserState.snapshotService.startCapture()
            }
            toolGridItem(icon: "clock.arrow.circlepath", label: "Timeline") {
                if let folderId = browserState.currentFolderId {
                    let timelineId = Note.timelineNoteId(forFolder: folderId)
                    browserState.openNoteTab(noteId: timelineId, title: "Timeline")
                }
            }
            toolGridItem(icon: "note.text", label: "New Note") {
                browserState.createNoteTab()
            }
        }
    }

    private func toolGridItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
    struct ArcSidebarView_Previews: PreviewProvider {
        static var previews: some View {
            ArcSidebarView(
                browserState: BrowserState(),
                appNav: AppNavigationState(),
                showCommandBar: .constant(false),
                isFullScreen: false,
                isSidebarCollapsed: .constant(false)
            )
            .frame(width: 280, height: 700)
            .background(Color.gray.opacity(0.2))
        }
    }
#endif
