// BrowserState.swift - Observable State Management
// Swift 6.2 with @Observable macro for reactive UI

import AppKit
import Foundation
import SwiftUI

// =============================================================================
// MARK: - Panel Mode Enum
// =============================================================================

/// Represents the current mode of the left sidebar panel
enum PanelMode: String, Codable {
    case tab  // Traditional tab tree view
    case plan  // Plan mode with intent-driven planning
    case agent  // Agent mode with agentic execution
}

// =============================================================================
// MARK: - Browser State (Observable)
// =============================================================================

/// Central state container for the browser application
/// Uses Swift 6.2 @Observable macro for low-overhead reactive updates
/// All properties trigger view updates automatically when modified
/// Tab management is delegated to TabManager for single-responsibility
@Observable
@MainActor
final class BrowserState {

    // MARK: - Sub-Managers

    /// Dedicated manager for tab state and operations
    let tabManager: TabManager

    /// Dedicated manager for navigation state (per active tab)
    let navigationState: NavigationState

    /// Dedicated manager for desktop folders
    let folderManager: FolderManager

    /// Floating dock state
    let floatingDockState: FloatingDockState

    /// App settings manager
    let settingsManager: SettingsManager
    
    /// Extension manager for Chrome extensions
    let extensionManager: ExtensionManager

    // MARK: - Tab State (Delegating to TabManager)

    /// List of all open tabs (delegated to TabManager)
    var tabs: [Tab] { tabManager.tabs }

    /// Currently active tab index (delegated to TabManager)
    var activeTabIndex: Int { tabManager.activeTabIndex }

    /// Currently active tab (delegated to TabManager)
    var activeTab: Tab? { tabManager.activeTab }

    // MARK: - Folder State

    /// The folder currently open in the browser (nil when on homescreen)
    var currentFolderId: UUID?

    // MARK: - Navigation State (Delegating to NavigationState)

    /// Current URL in the address bar (for editing)
    /// Backward compatibility: forwards to navigationState
    var addressBarText: String {
        get { navigationState.addressBarText }
        set { navigationState.addressBarText = newValue }
    }

    /// Whether the current page is loading
    /// Backward compatibility: forwards to navigationState
    var isLoading: Bool { navigationState.isLoading }

    /// Whether back navigation is available
    /// Backward compatibility: forwards to navigationState
    var canGoBack: Bool { navigationState.canGoBack }

    /// Whether forward navigation is available
    /// Backward compatibility: forwards to navigationState
    var canGoForward: Bool { navigationState.canGoForward }

    // MARK: - UI State

    /// Current panel mode (tab tree or plan mode)
    var currentPanelMode: PanelMode = .tab

    /// Plan state for Plan Mode (shared across app)
    var planState: PlanState = PlanState()
    
    /// Agent state for Agent Mode (shared across app)
    var agentState: AgentState = AgentState()

    /// Whether the sidebar is visible
    var isSidebarVisible: Bool = true

    /// Width of the sidebar in points
    var sidebarWidth: CGFloat = 280

    /// Tab IDs currently displayed in the split view canvas
    /// Used to highlight tabs in the sidebar that are already open in a split pane
    var splitTabIds: Set<UUID> = []

    /// Saved split groups (contains tab IDs and layout info)
    /// When a split view is saved and the user opens a new tab, this stores the split configuration
    /// so the user can click on the group to restore the split view
    /// Supports multiple saved groups so users can create many splits without losing previous ones
    var savedSplitGroups: [SplitGroup] = []

    // MARK: - AI Sidecar State

    /// Whether the Python sidecar is connected
    var isSidecarConnected: Bool = false

    /// Last AI analysis result
    var lastAnalysisResult: String?

    /// Whether the settings view is visible
    var isSettingsVisible: Bool = false

    // MARK: - Storage Keys

    private static let foldersStorageKey = "bowser.folders"

    // MARK: - Initialization

    init() {
        // Initialize all sub-managers first (before capturing self in callbacks)
        self.settingsManager = SettingsManager()  // Initialize SettingsManager
        self.navigationState = NavigationState(settingsManager: self.settingsManager)  // Inject settings

        // Initialize TabManager with startup logic
        let startupTabs: [Tab]
        switch self.settingsManager.onStartup {
        case .newTab:
            startupTabs = [Tab(url: URL(string: "https://www.google.com")!, title: "Google")]
        case .continueWhereLeftOff:
            // TODO: Implement persistence recovery
            startupTabs = [Tab(url: URL(string: "https://www.google.com")!, title: "Google")]
        case .specificPages:
            // TODO: Implement specific pages
            startupTabs = [Tab(url: URL(string: "https://www.google.com")!, title: "Google")]
        }
        self.tabManager = TabManager(tabs: startupTabs)

        // Initialize FolderManager with UserDefaults persistence handlers
        self.folderManager = FolderManager(
            persistenceHandler: { data in
                UserDefaults.standard.set(data, forKey: Self.foldersStorageKey)
            },
            loadHandler: {
                UserDefaults.standard.data(forKey: Self.foldersStorageKey)
            }
        )

        // Initialize FloatingDockState
        self.floatingDockState = FloatingDockState()
        
        // Initialize ExtensionManager (must be done before loading extensions)
        self.extensionManager = ExtensionManager(browserState: nil)

        // Set initial address bar text
        navigationState.addressBarText = "https://www.google.com"

        // Set callbacks after self is fully initialized
        tabManager.onTabClosed = { tabId in
            // Clean up persistent browser when tab is closed
            BrowserManager.shared.closeBrowser(for: tabId)
        }

        tabManager.onActiveTabChanged = { [weak self] tab in
            // Sync navigation state when active tab changes
            guard let self else { return }
            if let tab {
                self.navigationState.syncFromTab(tab)
            }
        }
        
        // configure AI Services with saved api key (async, run in Task)
        if !self.settingsManager.aiApiKey.isEmpty {
            Task { @MainActor in
                try? await AIService.shared.configureAI(
                    provider: self.settingsManager.aiProvider.rawValue.lowercased(),
                    apiKey: self.settingsManager.aiApiKey
                )
                print("[BrowserState] AI Secret configured!")
            }
        }

        // Set browserState reference in extensionManager after self is initialized
        // This allows extensionManager to open tabs
        Task { @MainActor in
            // Use a small delay to ensure BrowserState is fully initialized
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            self.extensionManager.browserState = self
            
            // Load persisted extensions
            self.extensionManager.loadPersistedExtensions()
        }
    }

    // MARK: - Tab Actions (Delegating to TabManager)

    /// Create a new tab and make it active
    @discardableResult
    func createTab(url: URL = URL(string: "https://www.google.com")!) -> Tab {
        let tab = tabManager.createTab(url: url)
        addressBarText = tab.url.absoluteString
        return tab
    }

    /// Close a tab by index
    func closeTab(at index: Int) {
        tabManager.closeTab(at: index)
    }

    /// Close a specific tab
    func closeTab(_ tab: Tab) {
        tabManager.closeTab(tab)
    }

    /// Select a specific tab
    func selectTab(_ tab: Tab) {
        print("[BrowserState] Tab switched to: \(tab)")
        tabManager.selectTab(tab)
        addressBarText = tab.url.absoluteString
    }

    /// Update the cached preview for a specific tab
    func updateTabPreview(tabId: UUID, preview: NSImage?) {
        tabManager.updateTabPreview(tabId: tabId, preview: preview)
    }

    /// Toggle pin state for a tab
    func togglePin(_ tab: Tab) {
        tabManager.togglePin(tab)
    }

    /// Move a tab to a new position (for drag-drop reordering)
    func moveTab(_ sourceId: UUID, before targetId: UUID) {
        tabManager.moveTab(sourceId, before: targetId)
    }

    /// Update the current tab's active pane loading state and metadata
    func updateActiveTab(
        url: URL? = nil, title: String? = nil, isLoading: Bool? = nil, canGoBack: Bool? = nil,
        canGoForward: Bool? = nil
    ) {
        tabManager.updateTab(
            url: url, title: title, isLoading: isLoading, canGoBack: canGoBack,
            canGoForward: canGoForward)

        // Sync navigation state
        if let url { navigationState.addressBarText = url.absoluteString }
        navigationState.update(
            isLoading: isLoading, canGoBack: canGoBack, canGoForward: canGoForward)
    }

    /// Update the icon (favicon) for a specific pane
    func updatePaneIcon(paneId: UUID, icon: NSImage?) {
        tabManager.updatePaneIcon(paneId: paneId, icon: icon)
    }

    /// Update icon for the active pane in the active tab
    func updateActiveTabIcon(_ icon: NSImage?) {
        tabManager.updateActiveTabIcon(icon)
    }

    /// Save the current split layout as a group and switch to single tab view
    func saveSplitAndShowSingleTab(newTabId: UUID) {
        guard splitTabIds.count > 1 else { return }

        // Post notification to get current split layout from coordinator
        // The coordinator will create the group and update BrowserState
        NotificationCenter.default.post(
            name: .saveSplitAndShowSingleTab,
            object: nil,
            userInfo: ["newTabId": newTabId]
        )
    }

    /// Restore a saved split group
    func restoreSplitGroup(_ group: SplitGroup) {
        guard group.isValid(tabs: tabs) else {
            print("[BrowserState] Split group is invalid - some tabs no longer exist")
            removeSplitGroup(group)
            return
        }

        // Post notification to coordinator to restore the split layout
        NotificationCenter.default.post(
            name: .restoreSplitGroup,
            object: nil,
            userInfo: ["group": group]
        )

        // NOTE: We do NOT remove the group from savedSplitGroups here
        // The group stays in the list to maintain its position
        // The sidebar will render it as "active" based on splitTabIds matching
    }

    /// Update or create a split group based on the current layout
    /// If any existing group shares tabs with the new layout, update that group
    /// Otherwise, create a new group
    func updateOrCreateSplitGroup(rootNode: SplitNode) {
        let newTabIds = Set(rootNode.allTabIds)

        // Only save groups with 2+ tabs
        guard newTabIds.count >= 2 else { return }

        // Check if any existing group overlaps with these tabs
        if let existingIndex = savedSplitGroups.firstIndex(where: { group in
            let existingTabIds = Set(group.tabIds)
            return !existingTabIds.isDisjoint(with: newTabIds)
        }) {
            // Update the existing group with new rootNode
            savedSplitGroups[existingIndex] = SplitGroup(rootNode: rootNode)
            print("[BrowserState] Updated existing split group with \(newTabIds.count) tabs")
        } else {
            // Create new group
            savedSplitGroups.append(SplitGroup(rootNode: rootNode))
            print("[BrowserState] Created new split group with \(newTabIds.count) tabs")
        }
    }

    /// Save a split group (adds to array, avoids duplicates) - legacy method
    func saveSplitGroup(_ group: SplitGroup) {
        // Use the new updateOrCreate method
        updateOrCreateSplitGroup(rootNode: group.rootNode)
    }

    /// Remove a saved split group
    func removeSplitGroup(_ group: SplitGroup) {
        savedSplitGroups.removeAll { $0.id == group.id }
    }

    /// Clear invalid split groups (tabs no longer exist)
    func clearInvalidSplitGroups() {
        savedSplitGroups.removeAll { !$0.isValid(tabs: tabs) }
    }

    /// Remove a tab from any split groups it belongs to
    /// If the group has only 1 tab remaining, remove the group entirely
    func removeTabFromSplitGroups(_ tabId: UUID) {
        var groupsToRemove: [UUID] = []

        for (index, group) in savedSplitGroups.enumerated() {
            if group.tabIds.contains(tabId) {
                // Remove the tab from this group's rootNode
                if let newRoot = removeTabFromNode(tabId, in: group.rootNode) {
                    // Check if only one tab remains
                    if newRoot.allTabIds.count <= 1 {
                        // Group has 0-1 tabs remaining, mark for removal
                        groupsToRemove.append(group.id)
                    } else {
                        // Update the group with new rootNode
                        savedSplitGroups[index] = SplitGroup(rootNode: newRoot)
                    }
                } else {
                    // Node was completely removed
                    groupsToRemove.append(group.id)
                }

                // If this was the active split, clear splitTabIds
                if splitTabIds.contains(tabId) {
                    // Update splitTabIds to remove this tab
                    splitTabIds.remove(tabId)
                }
            }
        }

        // Remove groups that are now invalid
        savedSplitGroups.removeAll { groupsToRemove.contains($0.id) }
    }

    /// Remove a tab from a SplitNode, returning the new node or nil if empty
    private func removeTabFromNode(_ tabId: UUID, in node: SplitNode) -> SplitNode? {
        switch node {
        case .pane(_, let paneTabId):
            // If this pane has the tab, remove it
            return paneTabId == tabId ? nil : node

        case .split(let id, let axis, let children, let proportions):
            var newChildren: [SplitNode] = []
            var newProportions: [CGFloat] = []

            for (index, child) in children.enumerated() {
                if let remaining = removeTabFromNode(tabId, in: child) {
                    newChildren.append(remaining)
                    if index < proportions.count {
                        newProportions.append(proportions[index])
                    }
                }
            }

            // Normalize proportions
            let total = newProportions.reduce(0, +)
            if total > 0 {
                newProportions = newProportions.map { $0 / total }
            }

            // Return based on remaining children
            switch newChildren.count {
            case 0:
                return nil
            case 1:
                return newChildren[0]
            default:
                return .split(
                    id: id, axis: axis, children: newChildren, proportions: newProportions)
            }
        }
    }

    // MARK: - Folder Actions

    /// Load a folder's tabs and plans, replacing the current browser session.
    /// Saves current folder before switching.
    func loadFolder(id folderId: UUID) {
        // Save current folder's tabs before switching
        saveCurrentFolder()

        // Load persisted tabs for this folder
        let persistence = FolderTabPersistence.shared
        if let savedTabs = persistence.loadTabs(forFolder: folderId), !savedTabs.isEmpty {
            tabManager.replaceTabs(savedTabs)
        } else {
            // Fresh folder: start with a single Google tab
            tabManager.replaceTabs([Tab(url: URL(string: "https://www.google.com")!, title: "Google")])
        }

        // Reset navigation state for new session
        navigationState.addressBarText = activeTab?.url.absoluteString ?? "https://www.google.com"

        // Scope plan storage to this folder
        planState = PlanState(storageManager: PlanStorageManager(folderId: folderId))

        // Reset agent state for new folder context
        agentState = AgentState()

        currentFolderId = folderId
        print("[BrowserState] Loaded folder \(folderId)")
    }

    /// Persist the current tabs for the active folder.
    /// Filters out quick-access dock tabs so they don't pollute folder contents.
    func saveCurrentFolder() {
        guard let folderId = currentFolderId else { return }
        let dockTabIds = Set(floatingDockState.quickAccessTabs.values)
        let folderTabs = tabManager.tabs.filter { !dockTabIds.contains($0.id) }
        FolderTabPersistence.shared.saveTabs(folderTabs, forFolder: folderId)
        print("[BrowserState] Saved folder \(folderId)")
    }

    /// Create a new folder and immediately open it in the browser.
    @discardableResult
    func createFolder(name: String) -> Folder {
        folderManager.createFolder(name: name)
    }

    // MARK: - Navigation Actions

    /// Navigate the active tab to a new URL
    /// Posts a notification for the CEF browser view to handle
    func navigateToURL(_ url: URL) {
        // Update the active pane's URL and loading state
        tabManager.updateTab(url: url, isLoading: true)

        // Update navigation state
        navigationState.addressBarText = url.absoluteString
        navigationState.update(isLoading: true)

        // Post notification for CEF browser view
        NotificationCenter.default.post(
            name: .navigateToURL,
            object: nil,
            userInfo: ["url": url]
        )
    }
}

// =============================================================================
// MARK: - WebPane Model (Split View Support)
// =============================================================================

/// Represents a single web pane within a split tab
/// Each pane has its own URL, title, favicon, and loading state
/// Uses @unchecked Sendable since NSImage is not Sendable but all UI updates occur on MainActor
struct WebPane: Identifiable, Equatable, @unchecked Sendable {
    let id: UUID
    var url: URL
    var title: String
    var favicon: Data?
    var icon: NSImage?  // Loaded favicon image for display
    var isLoading: Bool
    var canGoBack: Bool
    var canGoForward: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        title: String = "Google",
        favicon: Data? = nil,
        icon: NSImage? = nil,
        isLoading: Bool = false,
        canGoBack: Bool = false,
        canGoForward: Bool = false
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.favicon = favicon
        self.icon = icon
        self.isLoading = isLoading
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }

    // Custom Equatable (NSImage by reference)
    static func == (lhs: WebPane, rhs: WebPane) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url && lhs.title == rhs.title
            && lhs.favicon == rhs.favicon && lhs.icon === rhs.icon && lhs.isLoading == rhs.isLoading
            && lhs.canGoBack == rhs.canGoBack && lhs.canGoForward == rhs.canGoForward
    }
}

// =============================================================================
// MARK: - Split Group Model
// =============================================================================

/// Represents a saved split view configuration
/// When the user has a split view open and creates a new tab, the split is saved as a group
/// The user can click on the group in the sidebar to restore the split layout
/// Stores the full SplitNode tree to preserve exact positions and nesting
struct SplitGroup: Identifiable, Equatable {
    let id: UUID

    /// The full split tree structure (preserves positions and nesting)
    var rootNode: SplitNode

    /// Timestamp when the group was created (for sorting/display)
    var createdAt: Date

    /// Tab IDs in this split group (computed from rootNode for compatibility)
    var tabIds: [UUID] {
        rootNode.allTabIds
    }

    /// The split axis (computed from rootNode)
    var axis: SplitAxis {
        switch rootNode {
        case .pane:
            return .horizontal  // Default for single pane
        case .split(_, let axis, _, _):
            return axis
        }
    }

    init(rootNode: SplitNode) {
        self.id = UUID()
        self.rootNode = rootNode
        self.createdAt = Date()
    }

    /// Combined title from all tabs in the group
    func combinedTitle(tabs: [Tab]) -> String {
        let groupTabs = tabIds.compactMap { tabId in
            tabs.first { $0.id == tabId }
        }
        if groupTabs.isEmpty {
            return "Split Group"
        }
        return groupTabs.map { $0.title.isEmpty ? "Google" : $0.title }.joined(separator: " | ")
    }

    /// Check if all tabs in the group still exist
    func isValid(tabs: [Tab]) -> Bool {
        let existingTabIds = Set(tabs.map { $0.id })
        return tabIds.allSatisfy { existingTabIds.contains($0) }
    }
}

// =============================================================================
// MARK: - Tab Model
// =============================================================================

/// Represents a browser tab with a single web pane.
///
/// Note: The `panes` array always contains exactly one pane. Split views are handled
/// via the `SplitNode` tree structure in `SplitCanvasView`, where multiple separate
/// tabs are displayed side-by-side rather than multiple panes within a single tab.
///
/// Uses @unchecked Sendable since NSImage is not Sendable but all UI updates occur on MainActor.
struct Tab: Identifiable, Equatable, @unchecked Sendable {
    let id: UUID

    /// Parent tab ID for tree hierarchy (nil = root tab)
    /// When a tab is opened from another tab, this stores the parent's ID
    var parentTabId: UUID?

    /// The single web pane for this tab.
    /// Note: This is an array for historical reasons but always contains exactly one pane.
    var panes: [WebPane]

    /// ID of the pane (matches the single pane in `panes` array)
    var activePaneId: UUID

    /// Tab-level properties
    var isPinned: Bool
    var cachedPreview: NSImage?  // Tab preview snapshot for hover display

    // MARK: - Stacked Page Navigation

    /// Whether stack mode is enabled for this tab
    /// When enabled, link clicks spawn new pages in a horizontal stack
    var stackModeEnabled: Bool

    /// Pages in the horizontal stack (only used when stackModeEnabled = true)
    /// When stackModeEnabled = false, this array is empty and navigation uses panes
    var pages: [Page]

    /// Index of the currently active page in the stack
    var activePageIndex: Int

    // MARK: - Computed Properties

    /// Currently active/focused pane
    var activePane: WebPane? {
        panes.first { $0.id == activePaneId }
    }

    /// Currently active page (when stack mode is enabled)
    var activePage: Page? {
        guard stackModeEnabled, pages.indices.contains(activePageIndex) else { return nil }
        return pages[activePageIndex]
    }

    /// URL of the active pane or page (for URL bar display)
    var activePaneURL: URL {
        if stackModeEnabled, let page = activePage {
            return page.url
        }
        return activePane?.url ?? panes.first?.url ?? URL(string: "https://www.google.com")!
    }

    /// Title of the active pane or page
    var activePaneTitle: String {
        if stackModeEnabled, let page = activePage {
            return page.title
        }
        return activePane?.title ?? panes.first?.title ?? "Google"
    }

    /// Whether any pane is loading (or active page in stack mode)
    var isLoading: Bool {
        if stackModeEnabled, let page = activePage {
            return page.isLoading
        }
        return panes.contains { $0.isLoading }
    }

    /// Loading state of active pane (or active page in stack mode)
    var activePaneIsLoading: Bool {
        if stackModeEnabled, let page = activePage {
            return page.isLoading
        }
        return activePane?.isLoading ?? false
    }

    /// Navigation state from active pane (or active page in stack mode)
    var canGoBack: Bool {
        if stackModeEnabled, let page = activePage {
            return page.canGoBack
        }
        return activePane?.canGoBack ?? false
    }

    var canGoForward: Bool {
        if stackModeEnabled, let page = activePage {
            return page.canGoForward
        }
        return activePane?.canGoForward ?? false
    }

    /// Primary favicon (active page in stack mode, or first pane)
    var icon: NSImage? {
        if stackModeEnabled, let page = activePage {
            return page.icon
        }
        return activePane?.icon ?? panes.first?.icon
    }

    /// Primary favicon data (active page in stack mode, or first pane)
    var favicon: Data? {
        if stackModeEnabled, let page = activePage {
            return page.favicon
        }
        return activePane?.favicon ?? panes.first?.favicon
    }

    // MARK: - Legacy Compatibility

    /// URL property for backwards compatibility (returns active pane URL)
    var url: URL {
        get { activePaneURL }
        set {
            if let index = panes.firstIndex(where: { $0.id == activePaneId }) {
                panes[index].url = newValue
            }
        }
    }

    /// Title property for backwards compatibility
    var title: String {
        get { activePaneTitle }
        set {
            if let index = panes.firstIndex(where: { $0.id == activePaneId }) {
                panes[index].title = newValue
            }
        }
    }

    // MARK: - Initialization

    /// Create a tab with a single pane (default case)
    init(
        id: UUID = UUID(),
        parentTabId: UUID? = nil,
        url: URL,
        title: String = "Google",
        favicon: Data? = nil,
        icon: NSImage? = nil,
        isLoading: Bool = false,
        isPinned: Bool = false,
        cachedPreview: NSImage? = nil,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        stackModeEnabled: Bool = false
    ) {
        self.id = id
        self.parentTabId = parentTabId
        let pane = WebPane(
            url: url,
            title: title,
            favicon: favicon,
            icon: icon,
            isLoading: isLoading,
            canGoBack: canGoBack,
            canGoForward: canGoForward
        )
        self.panes = [pane]
        self.activePaneId = pane.id
        self.isPinned = isPinned
        self.cachedPreview = cachedPreview

        // Stack mode initialization
        self.stackModeEnabled = stackModeEnabled
        self.pages = []
        self.activePageIndex = 0
    }

    // MARK: - Pane Mutations

    /// Update a specific pane's properties
    mutating func updatePane(
        _ paneId: UUID, url: URL? = nil, title: String? = nil, isLoading: Bool? = nil,
        canGoBack: Bool? = nil, canGoForward: Bool? = nil
    ) {
        guard let index = panes.firstIndex(where: { $0.id == paneId }) else { return }
        if let url { panes[index].url = url }
        if let title { panes[index].title = title }
        if let isLoading { panes[index].isLoading = isLoading }
        if let canGoBack { panes[index].canGoBack = canGoBack }
        if let canGoForward { panes[index].canGoForward = canGoForward }
    }

    /// Update a specific pane's icon
    mutating func updatePaneIcon(_ paneId: UUID, icon: NSImage?, favicon: Data? = nil) {
        guard let index = panes.firstIndex(where: { $0.id == paneId }) else { return }
        panes[index].icon = icon
        if let favicon { panes[index].favicon = favicon }
    }

    // Custom Equatable implementation (NSImage comparison by reference)
    static func == (lhs: Tab, rhs: Tab) -> Bool {
        lhs.id == rhs.id && lhs.parentTabId == rhs.parentTabId && lhs.panes == rhs.panes
            && lhs.activePaneId == rhs.activePaneId && lhs.isPinned == rhs.isPinned
            && lhs.cachedPreview === rhs.cachedPreview
            && lhs.stackModeEnabled == rhs.stackModeEnabled && lhs.pages == rhs.pages
            && lhs.activePageIndex == rhs.activePageIndex
    }
}
