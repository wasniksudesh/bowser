// TabTreeView.swift - Recursive Tab Tree Renderer
// Renders tabs in a hierarchical tree structure for the sidebar
// Supports infinite nesting levels with Apple-style curved connectors
// 
// PERFORMANCE OPTIMIZATIONS:
// 1. Pre-computed tree structure to avoid repeated filtering
// 2. Flattened rendering to avoid deep recursive view hierarchies
// 3. id-based ForEach to enable efficient diffing
// 4. Cached tree structure to prevent recomputation on every frame
// 5. Stable identity keys to prevent view thrashing

import SwiftUI

// =============================================================================
// MARK: - Tree Node Model
// =============================================================================

/// Pre-computed tree node for efficient rendering
/// Contains all information needed to render a tab row without re-computation
struct TabTreeNode: Identifiable, Equatable {
    let id: UUID
    let tab: Tab
    let depth: Int
    let isLast: Bool
    let ancestorIsLast: [Bool]
    let hasChildren: Bool
    var isExpanded: Bool
    
    init(tab: Tab, depth: Int, isLast: Bool, ancestorIsLast: [Bool], hasChildren: Bool, isExpanded: Bool) {
        self.id = tab.id
        self.tab = tab
        self.depth = depth
        self.isLast = isLast
        self.ancestorIsLast = ancestorIsLast
        self.hasChildren = hasChildren
        self.isExpanded = isExpanded
    }
    
    static func == (lhs: TabTreeNode, rhs: TabTreeNode) -> Bool {
        // PERFORMANCE: Only compare structural properties that affect tree layout
        // Do NOT compare tab.title, tab.favicon, etc. - those are handled by TabTreeRowView's own state
        // This prevents full tree rebuilds when only a tab's metadata changes
        lhs.id == rhs.id &&
        lhs.tab.id == rhs.tab.id &&
        lhs.tab.parentTabId == rhs.tab.parentTabId &&
        lhs.depth == rhs.depth &&
        lhs.isLast == rhs.isLast &&
        lhs.hasChildren == rhs.hasChildren &&
        lhs.isExpanded == rhs.isExpanded
    }
}

// =============================================================================
// MARK: - Cached Tree Structure
// =============================================================================

/// Cached tree structure for efficient lookup and traversal
/// Computed once per tabs array change, not on every view update
struct CachedTreeStructure {
    let childrenMap: [UUID: [Tab]]
    let rootTabs: [Tab]
    let tabIds: Set<UUID>
    
    init(tabs: [Tab]) {
        var childrenMap: [UUID: [Tab]] = [:]
        var rootTabs: [Tab] = []
        let tabIds = Set(tabs.map { $0.id })
        
        for tab in tabs {
            if let parentId = tab.parentTabId, tabIds.contains(parentId) {
                childrenMap[parentId, default: []].append(tab)
            } else {
                rootTabs.append(tab)
            }
        }
        
        self.childrenMap = childrenMap
        self.rootTabs = rootTabs
        self.tabIds = tabIds
    }
}

// =============================================================================
// MARK: - Tab Tree View
// =============================================================================

/// Recursive tree renderer for hierarchical tab display
/// Computes parent-child relationships and renders tabs with proper indentation
/// 
/// PERFORMANCE: Uses pre-computed flat list for O(1) rendering instead of
/// recursive view building which causes O(n²) SwiftUI diffing
struct TabTreeView: View {
    
    @Bindable var browserState: BrowserState
    let tabs: [Tab]
    
    let onSelect: (Tab) -> Void
    let onClose: (Tab) -> Void
    let onPin: (Tab) -> Void
    let onOpenChildTab: (Tab) -> Void
    
    /// Tracks which parent tabs are collapsed
    @State private var collapsedTabIds: Set<UUID> = []
    
    /// Tracks which tab is currently being dragged (for split view drag-drop)
    @State private var draggedTab: Tab? = nil
    
    /// Cached tree structure - recomputed only when tabs array changes
    @State private var cachedTree: CachedTreeStructure?
    
    /// Cached visible nodes - recomputed when tree or collapse state changes
    @State private var cachedNodes: [TabTreeNode] = []
    
    /// Last known tabs array signature for cache invalidation
    @State private var lastTabsSignature: String = ""
    
    /// Efficient signature for detecting tab array changes
    /// PERFORMANCE: Uses count + first/last IDs instead of mapping entire array
    private var tabsSignature: String {
        guard !tabs.isEmpty else { return "empty" }
        // Include count, first ID, last ID, and parent structure checksum
        let parentChecksum = tabs.reduce(0) { $0 &+ ($1.parentTabId?.hashValue ?? 0) }
        return "\(tabs.count)-\(tabs.first!.id)-\(tabs.last!.id)-\(parentChecksum)"
    }
    
    /// Pre-computed visible nodes (uses cache when possible)
    /// Falls back to direct computation if cache is empty to ensure tabs are always visible
    private var visibleNodes: [TabTreeNode] {
        // If cache is populated and up-to-date, use it
        if !cachedNodes.isEmpty {
            return cachedNodes
        }
        // Fallback: compute directly if cache is not ready
        // This handles the initial render before task/onAppear fires
        return computeVisibleNodes()
    }
    
    var body: some View {
        // Use LazyVStack for virtualization of large tab lists
        // id: parameter ensures stable identity for smooth animations
        // 
        // IMPORTANT: We use Group instead of just ForEach because ForEach with
        // an initially empty array won't trigger onAppear reliably. The Group
        // ensures the modifiers are applied even when visibleNodes starts empty.
        Group {
            ForEach(visibleNodes) { node in
                TabTreeRowView(
                    tab: node.tab,
                    depth: node.depth,
                    hasChildren: node.hasChildren,
                    isExpanded: node.isExpanded,
                    isActive: browserState.activeTab?.id == node.tab.id,
                    isInSplit: browserState.splitTabIds.contains(node.tab.id),
                    isLastChild: node.isLast,
                    ancestorIsLast: node.ancestorIsLast,
                    onSelect: { onSelect(node.tab) },
                    onClose: { onClose(node.tab) },
                    onPin: { onPin(node.tab) },
                    onToggleExpand: {
                        toggleExpand(node.tab.id)
                    },
                    onOpenChildTab: { onOpenChildTab(node.tab) }
                )
                // Enable drag support for split view
                // Uses custom AppKit wrapper to prevent window movement during drags
                .draggableTab(tabId: node.tab.id, draggedTab: $draggedTab, tab: node.tab)
                // Enable drop support for tab reordering
                .onDrop(of: [.text], delegate: TabDropDelegate(
                    tab: node.tab,
                    draggedTab: $draggedTab,
                    browserState: browserState
                ))
            }
        }
        // Use task instead of onAppear for more reliable initialization
        // task runs asynchronously after the view appears, ensuring state is ready
        .task {
            rebuildCacheIfNeeded()
        }
        // PERFORMANCE: Use tabs.count and id of first/last tab as a proxy for array changes
        // This avoids creating a new array on every render just to compare identities
        .onChange(of: tabsSignature) { _, _ in
            rebuildCacheIfNeeded()
        }
        .onChange(of: collapsedTabIds) {
            rebuildNodesFromCache()
        }
    }
    
    // MARK: - Expand/Collapse with Optimized Updates
    
    /// Toggle expand state without full recomputation
    private func toggleExpand(_ tabId: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if collapsedTabIds.contains(tabId) {
                collapsedTabIds.remove(tabId)
            } else {
                collapsedTabIds.insert(tabId)
            }
        }
    }
    
    // MARK: - Cache Management
    
    /// Rebuild cache only if tabs have changed
    /// PERFORMANCE: Uses the efficient tabsSignature instead of rebuilding a full string
    private func rebuildCacheIfNeeded() {
        let signature = tabsSignature
        guard signature != lastTabsSignature else { return }
        
        lastTabsSignature = signature
        cachedTree = CachedTreeStructure(tabs: tabs)
        rebuildNodesFromCache()
    }
    
    /// Rebuild visible nodes using cached tree structure
    private func rebuildNodesFromCache() {
        guard let tree = cachedTree else {
            cachedNodes = computeVisibleNodes()
            return
        }
        cachedNodes = computeVisibleNodesFromCache(tree)
    }
    
    // MARK: - Tree Computation (Optimized with Cache)
    
    /// Compute visible nodes using pre-cached tree structure
    private func computeVisibleNodesFromCache(_ tree: CachedTreeStructure) -> [TabTreeNode] {
        var nodes: [TabTreeNode] = []
        nodes.reserveCapacity(tabs.count)
        
        func addNode(_ tab: Tab, depth: Int, isLast: Bool, ancestorIsLast: [Bool]) {
            let children = tree.childrenMap[tab.id] ?? []
            let isExpanded = !collapsedTabIds.contains(tab.id)
            
            nodes.append(TabTreeNode(
                tab: tab,
                depth: depth,
                isLast: isLast,
                ancestorIsLast: ancestorIsLast,
                hasChildren: !children.isEmpty,
                isExpanded: isExpanded
            ))
            
            // Only add children if expanded
            if isExpanded && !children.isEmpty {
                let childAncestorIsLast = ancestorIsLast + [isLast]
                for (index, child) in children.enumerated() {
                    addNode(child, depth: depth + 1, isLast: index == children.count - 1, ancestorIsLast: childAncestorIsLast)
                }
            }
        }
        
        // Process root tabs
        for (index, rootTab) in tree.rootTabs.enumerated() {
            addNode(rootTab, depth: 0, isLast: index == tree.rootTabs.count - 1, ancestorIsLast: [])
        }
        
        return nodes
    }
    
    // MARK: - Tree Computation (Fallback)
    
    /// Pre-compute the visible nodes as a flat list (fallback when cache not ready)
    /// This avoids recursive view building and enables efficient SwiftUI diffing
    private func computeVisibleNodes() -> [TabTreeNode] {
        // Build lookup tables once (O(n))
        let tabIds = Set(tabs.map { $0.id })
        var childrenMap: [UUID: [Tab]] = [:]
        var rootTabs: [Tab] = []
        
        for tab in tabs {
            if let parentId = tab.parentTabId, tabIds.contains(parentId) {
                childrenMap[parentId, default: []].append(tab)
            } else {
                rootTabs.append(tab)
            }
        }
        
        // Flatten tree into visible nodes list
        var nodes: [TabTreeNode] = []
        nodes.reserveCapacity(tabs.count) // Avoid reallocations
        
        func addNode(_ tab: Tab, depth: Int, isLast: Bool, ancestorIsLast: [Bool]) {
            let children = childrenMap[tab.id] ?? []
            let isExpanded = !collapsedTabIds.contains(tab.id)
            
            nodes.append(TabTreeNode(
                tab: tab,
                depth: depth,
                isLast: isLast,
                ancestorIsLast: ancestorIsLast,
                hasChildren: !children.isEmpty,
                isExpanded: isExpanded
            ))
            
            // Only add children if expanded
            if isExpanded && !children.isEmpty {
                let childAncestorIsLast = ancestorIsLast + [isLast]
                for (index, child) in children.enumerated() {
                    addNode(child, depth: depth + 1, isLast: index == children.count - 1, ancestorIsLast: childAncestorIsLast)
                }
            }
        }
        
        // Process root tabs
        for (index, rootTab) in rootTabs.enumerated() {
            addNode(rootTab, depth: 0, isLast: index == rootTabs.count - 1, ancestorIsLast: [])
        }
        
        return nodes
    }
}
