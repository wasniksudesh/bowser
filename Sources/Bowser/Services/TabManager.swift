// TabManager.swift - Dedicated Tab Management Service
// Extracted from BrowserState for single-responsibility
// Swift 6.2 with @Observable macro for reactive UI

import AppKit
import Foundation
import SwiftUI

// =============================================================================
// MARK: - Tab Manager
// =============================================================================

/// Dedicated manager for all tab-related state and operations
/// Uses Swift 6.2 @Observable macro for low-overhead reactive updates
/// Extracted from BrowserState God Object for single-responsibility
@Observable
@MainActor
final class TabManager {

    // MARK: - Core State

    /// List of all open tabs
    private(set) var tabs: [Tab] = [
        Tab(url: URL(string: "https://www.google.com")!, title: "Google")
    ]

    /// Currently active tab index
    private(set) var activeTabIndex: Int = 0

    // MARK: - Callbacks

    /// Called when a tab is closed - for browser cleanup (BrowserManager.closeBrowser)
    var onTabClosed: ((UUID) -> Void)?

    /// Called when active tab changes - for navigation state sync
    var onActiveTabChanged: ((Tab?) -> Void)?

    // MARK: - Computed Properties

    /// Currently active tab
    var activeTab: Tab? {
        get {
            guard tabs.indices.contains(activeTabIndex) else { return nil }
            return tabs[activeTabIndex]
        }
        set {
            if let newValue, let index = tabs.firstIndex(where: { $0.id == newValue.id }) {
                activeTabIndex = index
                onActiveTabChanged?(newValue)
            }
        }
    }

    /// ID of the currently active tab
    var activeTabId: UUID? {
        activeTab?.id
    }

    // MARK: - Cached Tab Lists (Performance Optimization)

    /// Cached pinned tabs - invalidated when tabs array changes
    private var cachedPinnedTabs: [Tab]?
    private var cachedUnpinnedTabs: [Tab]?
    private var lastTabsCount: Int = -1

    /// All pinned tabs (for sidebar pinned section)
    /// PERFORMANCE: Uses cached value when tabs haven't changed
    var pinnedTabs: [Tab] {
        if let cached = cachedPinnedTabs, tabs.count == lastTabsCount {
            return cached
        }
        let result = tabs.filter { $0.isPinned }
        // Note: Can't mutate self in getter, so caching happens in didSet observer below
        return result
    }

    /// All unpinned tabs (for sidebar main list)
    /// PERFORMANCE: Uses cached value when tabs haven't changed
    var unpinnedTabs: [Tab] {
        if let cached = cachedUnpinnedTabs, tabs.count == lastTabsCount {
            return cached
        }
        let result = tabs.filter { !$0.isPinned }
        return result
    }

    /// Invalidate caches when tabs change
    private func invalidateTabCaches() {
        cachedPinnedTabs = tabs.filter { $0.isPinned }
        cachedUnpinnedTabs = tabs.filter { !$0.isPinned }
        lastTabsCount = tabs.count
    }

    /// Total number of tabs
    var tabCount: Int {
        tabs.count
    }

    // MARK: - Initialization

    init(
        tabs: [Tab]? = nil,
        onTabClosed: ((UUID) -> Void)? = nil,
        onActiveTabChanged: ((Tab?) -> Void)? = nil
    ) {
        if let tabs, !tabs.isEmpty {
            self.tabs = tabs
        }
        self.onTabClosed = onTabClosed
        self.onActiveTabChanged = onActiveTabChanged
        // Initialize cache after tabs are set
        invalidateTabCaches()
    }

    /// Create a new tab and make it active
    /// - Parameters:
    ///   - url: URL to load in the new tab
    ///   - title: Initial title for the tab
    ///   - parentId: Optional parent tab ID for tree hierarchy
    /// - Returns: The newly created tab
    @discardableResult
    func createTab(
        url: URL = URL(string: "https://www.google.com")!, title: String = "Google",
        parentId: UUID? = nil
    ) -> Tab {
        let tab = Tab(parentTabId: parentId, url: url, title: title)
        tabs.append(tab)
        invalidateTabCaches()
        activeTabIndex = tabs.count - 1
        onActiveTabChanged?(tab)
        return tab
    }

    /// Create a note tab and make it active
    @discardableResult
    func createNoteTab(noteId: UUID, title: String = "Untitled Note") -> Tab {
        let tab = Tab(
            url: URL(string: "about:blank")!,
            title: title,
            tabType: .note,
            noteId: noteId
        )
        tabs.append(tab)
        invalidateTabCaches()
        activeTabIndex = tabs.count - 1
        onActiveTabChanged?(tab)
        return tab
    }

    /// Insert a tab into the tab list without changing the active tab.
    /// Used by the floating dock to register quick-access tabs with BrowserManager
    /// so that BrowserCanvas can create a CEF browser for previews.
    func insertBackgroundTab(_ tab: Tab) {
        guard !tabs.contains(where: { $0.id == tab.id }) else { return }
        tabs.append(tab)
        invalidateTabCaches()
    }

    /// Create a new child tab from an existing tab asynchronously
    /// The tab is created immediately but browser initialization happens in background
    /// - Parameters:
    ///   - url: URL to load in the new tab
    ///   - title: Initial title for the tab
    ///   - parentId: Parent tab ID (required)
    /// - Returns: The newly created child tab
    @discardableResult
    func createChildTab(url: URL, title: String = "New Tab", parentId: UUID) -> Tab {
        // Create tab synchronously (fast - just data structure)
        let tab = createTab(url: url, title: title, parentId: parentId)

        // Log for debugging
        print("[TabManager] Created child tab \(tab.id) with parent \(parentId)")

        return tab
    }

    /// Create a new child tab asynchronously without blocking
    /// Use this when you don't need the tab object immediately
    /// - Parameters:
    ///   - url: URL to load in the new tab
    ///   - title: Initial title for the tab
    ///   - parentId: Parent tab ID (required)
    func createChildTabAsync(url: URL, title: String = "New Tab", parentId: UUID) {
        // Use Task to avoid blocking the caller
        Task { @MainActor in
            _ = createChildTab(url: url, title: title, parentId: parentId)
        }
    }

    /// Close a tab by index
    /// - Parameter index: Index of the tab to close
    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }

        // Get tab and close all page browsers if in stack mode
        let tab = tabs[index]
        let tabId = tab.id

        // Close all browser instances for pages in this tab
        if tab.stackModeEnabled {
            let pageIds = tab.pages.map { $0.browserId }
            BrowserManager.shared.closeAllBrowsersForPages(pageIds: pageIds)
        }

        // Orphan any child tabs (promote them to root level)
        // This preserves user's open tabs when closing a parent
        orphanChildren(of: tabId)

        // Post notification for split canvas cleanup BEFORE removing the tab
        NotificationCenter.default.post(
            name: .tabWillClose,
            object: nil,
            userInfo: ["tabId": tabId]
        )

        // Remove tab from model
        tabs.remove(at: index)
        invalidateTabCaches()

        // Notify for browser cleanup (for non-stack mode tabs with single pane browser)
        onTabClosed?(tabId)

        // Ensure we always have at least one tab
        if tabs.isEmpty {
            _ = createTab()
        }

        // Adjust active index if needed
        if activeTabIndex >= tabs.count {
            activeTabIndex = max(0, tabs.count - 1)
        }

        onActiveTabChanged?(activeTab)
    }

    /// Orphan all child tabs of a given parent (promote to root level)
    /// Called when a parent tab is closed to preserve child tabs
    private func orphanChildren(of parentId: UUID) {
        var changed = false
        for index in tabs.indices {
            if tabs[index].parentTabId == parentId {
                tabs[index].parentTabId = nil
                changed = true
            }
        }
        if changed {
            invalidateTabCaches()
        }
    }

    /// Close a specific tab
    /// - Parameter tab: The tab to close
    func closeTab(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        closeTab(at: index)
    }

    /// Close a tab by ID
    /// - Parameter id: UUID of the tab to close
    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        closeTab(at: index)
    }

    /// Select a specific tab, making it active
    /// - Parameter tab: The tab to select
    func selectTab(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }

        // Don't switch to the same tab
        guard activeTab?.id != tab.id else { return }

        activeTabIndex = index
        onActiveTabChanged?(tab)
        print("[TabManager] Tab switched to: \(tab.title)")
    }

    /// Select a tab by its ID
    /// - Parameter id: UUID of the tab to select
    func selectTab(id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        selectTab(tab)
    }

    /// Find a tab by its ID
    /// - Parameter id: UUID of the tab to find
    /// - Returns: The tab if found, nil otherwise
    func tab(for id: UUID) -> Tab? {
        tabs.first { $0.id == id }
    }

    // MARK: - Tab Mutations

    /// Toggle pin state for a tab
    /// - Parameter tab: The tab to pin/unpin
    func togglePin(_ tab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tabs[index].isPinned.toggle()

        // Move pinned tabs to the beginning
        let pinned = tabs.filter { $0.isPinned }
        let unpinned = tabs.filter { !$0.isPinned }
        tabs = pinned + unpinned
        invalidateTabCaches()

        // Update active index if needed
        if let newIndex = tabs.firstIndex(where: { $0.id == tab.id }) {
            activeTabIndex = newIndex
        }
    }

    /// Move a tab to a new position (for drag-drop reordering)
    /// - Parameters:
    ///   - sourceId: UUID of the tab to move
    ///   - targetId: UUID of the tab to move before
    func moveTab(_ sourceId: UUID, before targetId: UUID) {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == sourceId }),
            let targetIndex = tabs.firstIndex(where: { $0.id == targetId }),
            sourceIndex != targetIndex
        else { return }

        let tab = tabs.remove(at: sourceIndex)
        let insertIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        tabs.insert(tab, at: insertIndex)
        invalidateTabCaches()

        // Update active index
        if let newActiveIndex = tabs.firstIndex(where: { $0.id == activeTab?.id }) {
            activeTabIndex = newActiveIndex
        }
    }

    /// Update the cached preview for a specific tab
    /// - Parameters:
    ///   - tabId: The tab's unique identifier
    ///   - preview: The snapshot NSImage to cache
    func updateTabPreview(tabId: UUID, preview: NSImage?) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else {
            print("[TabManager] updateTabPreview: Tab \(tabId) not found")
            return
        }
        tabs[index].cachedPreview = preview
        print(
            "[TabManager] Updated preview for tab \(tabId): \(preview != nil ? "\(Int(preview!.size.width))x\(Int(preview!.size.height))" : "nil")"
        )
    }

    /// Update the icon (favicon) for a specific pane
    /// - Parameters:
    ///   - paneId: The pane's unique identifier
    ///   - icon: The favicon NSImage to display
    func updatePaneIcon(paneId: UUID, icon: NSImage?) {
        // Find the tab containing this pane
        guard
            let tabIndex = tabs.firstIndex(where: { tab in
                tab.panes.contains { $0.id == paneId }
            })
        else { return }

        let favicon = icon?.tiffRepresentation
        tabs[tabIndex].updatePaneIcon(paneId, icon: icon, favicon: favicon)
    }

    /// Update icon for the active pane in the active tab
    /// - Parameter icon: The favicon NSImage to display
    func updateActiveTabIcon(_ icon: NSImage?) {
        guard var tab = activeTab else { return }
        let favicon = icon?.tiffRepresentation
        tab.updatePaneIcon(tab.activePaneId, icon: icon, favicon: favicon)
        tabs[activeTabIndex] = tab
    }

    /// Update a specific tab's active pane properties
    /// Called when navigation state changes (URL, title, loading, etc.)
    /// - Parameters:
    ///   - tabId: The tab's unique identifier (defaults to active tab)
    ///   - url: New URL (optional)
    ///   - title: New title (optional)
    ///   - isLoading: New loading state (optional)
    ///   - canGoBack: New back navigation state (optional)
    ///   - canGoForward: New forward navigation state (optional)
    func updateTab(
        id tabId: UUID? = nil,
        url: URL? = nil,
        title: String? = nil,
        isLoading: Bool? = nil,
        canGoBack: Bool? = nil,
        canGoForward: Bool? = nil
    ) {
        // Find the tab (default to active)
        let targetId = tabId ?? activeTabId
        guard let targetId,
            let index = tabs.firstIndex(where: { $0.id == targetId })
        else { return }

        var tab = tabs[index]
        let activePaneId = tab.activePaneId

        // Update the active pane within the tab
        tab.updatePane(
            activePaneId, url: url, title: title, isLoading: isLoading, canGoBack: canGoBack,
            canGoForward: canGoForward)
        tabs[index] = tab
    }

    /// Replace an entire tab with an updated version
    /// Used when making complex changes to tab state (e.g., page stack modifications)
    /// - Parameters:
    ///   - tabId: The tab's unique identifier
    ///   - updatedTab: The updated tab to replace the existing one
    func replaceTab(id tabId: UUID, with updatedTab: Tab) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[index] = updatedTab
        invalidateTabCaches()
    }

    /// Replace the entire tab list at once (used when switching folders).
    /// Closes all current browser instances before replacing.
    func replaceTabs(_ newTabs: [Tab]) {
        // Close all current browser instances
        for tab in tabs {
            onTabClosed?(tab.id)
        }

        tabs = newTabs.isEmpty
            ? [Tab(url: URL(string: "https://www.google.com")!, title: "Google")]
            : newTabs
        activeTabIndex = 0
        invalidateTabCaches()
        onActiveTabChanged?(activeTab)
        print("[TabManager] Replaced tabs with \(tabs.count) entries")
    }
}
