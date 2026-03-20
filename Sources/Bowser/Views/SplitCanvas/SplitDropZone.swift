// SplitDropZone.swift - Drop Zone Detection for VS Code-Style Splitting
// Bowser - Swift 6.2
// Defines drop zone regions and detection logic for split editor

import Foundation
import AppKit

// =============================================================================
// MARK: - Drop Zone Enum
// =============================================================================

/// Represents where a tab will be dropped within a pane
/// Only supports vertical (side-by-side) splits for a cleaner UX
public enum SplitDropZone: Equatable, Sendable {
    /// Drop in the left portion - creates vertical split, new pane on left
    case left
    
    /// Drop in the right portion - creates vertical split, new pane on right
    case right
    
    /// Drop in the center - adds tab to existing pane (no split)
    case center
    
    /// The split axis this drop zone implies (always horizontal/side-by-side)
    var splitAxis: SplitAxis? {
        switch self {
        case .left, .right: return .horizontal
        case .center: return nil
        }
    }
    
    /// Whether the new content should be inserted before (left) or after (right)
    var insertPosition: InsertPosition {
        switch self {
        case .left: return .before
        case .right: return .after
        case .center: return .replace
        }
    }
}

// =============================================================================
// MARK: - Split Axis
// =============================================================================

/// Axis for splitting - matches NSSplitView orientation.
///
/// Note: Currently only `.horizontal` (side-by-side) splits are supported.
/// The `.vertical` case (stacked top/bottom) is defined for potential future use
/// but the drop zone detection only supports left/right/center zones.
public enum SplitAxis: Sendable {
    case horizontal // Side-by-side (left/right) - currently the only supported mode
    case vertical   // Stacked (top/bottom) - reserved for future use
    
    /// NSSplitView isVertical value
    /// Note: NSSplitView.isVertical refers to the DIVIDER orientation, not the layout:
    /// - isVertical = true  → vertical divider → views arranged side-by-side (horizontal layout)
    /// - isVertical = false → horizontal divider → views stacked top-to-bottom (vertical layout)
    var isNSSplitViewVertical: Bool {
        switch self {
        case .horizontal: return true  // Side-by-side needs vertical divider
        case .vertical: return false   // Stacked needs horizontal divider
        }
    }
}

// =============================================================================
// MARK: - Insert Position
// =============================================================================

/// Where to insert the new pane relative to the existing one
public enum InsertPosition: Sendable {
    case before  // Insert at index 0 (left or top)
    case after   // Insert at index 1 (right or bottom)
    case replace // No split, replace or add to existing
}

// =============================================================================
// MARK: - Drop Zone Detector
// =============================================================================

/// Detects which drop zone the cursor is in based on position within bounds
public struct DropZoneDetector {
    
    /// Threshold for edge zones (20% of dimension)
    public static let edgeThreshold: CGFloat = 0.20
    
    /// Detect drop zone from point within bounds
    /// Only detects left/right/center zones (vertical splits only)
    /// - Parameters:
    ///   - point: The point in the view's coordinate system
    ///   - bounds: The view's bounds
    /// - Returns: The detected drop zone
    public static func detectZone(point: NSPoint, in bounds: NSRect) -> SplitDropZone {
        // Calculate relative horizontal position (0.0 - 1.0)
        let relativeX = (point.x - bounds.minX) / bounds.width
        
        // Only check left/right edges for vertical (side-by-side) splits
        
        // Left edge
        if relativeX < edgeThreshold {
            return .left
        }
        
        // Right edge
        if relativeX > (1.0 - edgeThreshold) {
            return .right
        }
        
        // Center (default)
        return .center
    }
    
    /// Calculate the highlight rect for a drop zone
    /// - Parameters:
    ///   - zone: The drop zone to highlight
    ///   - bounds: The container bounds
    /// - Returns: The rect to highlight
    public static func highlightRect(for zone: SplitDropZone, in bounds: NSRect) -> NSRect {
        // Use same proportions as actual split (50/50) with minimal visual inset
        let inset: CGFloat = 2 // Minimal inset for border visibility
        let insetBounds = bounds.insetBy(dx: inset, dy: inset)
        
        switch zone {
        case .left:
            return NSRect(
                x: insetBounds.minX,
                y: insetBounds.minY,
                width: insetBounds.width * 0.5,
                height: insetBounds.height
            )
            
        case .right:
            return NSRect(
                x: insetBounds.minX + insetBounds.width * 0.5,
                y: insetBounds.minY,
                width: insetBounds.width * 0.5,
                height: insetBounds.height
            )
            
        case .center:
            return insetBounds
        }
    }
}

// =============================================================================
// MARK: - Split Node
// =============================================================================

/// Represents a node in the split tree (either a leaf pane or a split container)
/// Enables infinite nesting like VS Code
public enum SplitNode: Identifiable, Equatable {
    /// A leaf node containing a single tab
    case pane(id: UUID, tabId: UUID)
    
    /// A split container with child nodes
    indirect case split(id: UUID, axis: SplitAxis, children: [SplitNode], proportions: [CGFloat])
    
    public var id: UUID {
        switch self {
        case .pane(let id, _): return id
        case .split(let id, _, _, _): return id
        }
    }
    
    /// Get the tab ID if this is a pane node
    public var tabId: UUID? {
        switch self {
        case .pane(_, let tabId): return tabId
        case .split: return nil
        }
    }
    
    /// All tab IDs contained in this node (recursively)
    public var allTabIds: [UUID] {
        switch self {
        case .pane(_, let tabId):
            return [tabId]
        case .split(_, _, let children, _):
            return children.flatMap { $0.allTabIds }
        }
    }
    
    /// Find a pane by tab ID
    public func findPane(tabId: UUID) -> UUID? {
        switch self {
        case .pane(let paneId, let tid):
            return tid == tabId ? paneId : nil
        case .split(_, _, let children, _):
            for child in children {
                if let found = child.findPane(tabId: tabId) {
                    return found
                }
            }
            return nil
        }
    }
    
    /// Update the tab ID for a specific pane
    public func updateTabId(paneId: UUID, newTabId: UUID) -> SplitNode {
        switch self {
        case .pane(let id, _):
            if id == paneId {
                return .pane(id: id, tabId: newTabId)
            }
            return self
            
        case .split(let id, let axis, let children, let proportions):
            let newChildren = children.map { child in
                child.updateTabId(paneId: paneId, newTabId: newTabId)
            }
            return .split(id: id, axis: axis, children: newChildren, proportions: proportions)
        }
    }
    
    /// Create a new tree by splitting a pane
    public func splitPane(
        paneId: UUID,
        newTabId: UUID,
        zone: SplitDropZone
    ) -> SplitNode {
        switch self {
        case .pane(let id, _):
            if id == paneId {
                // This is the pane to split
                guard let axis = zone.splitAxis else {
                    // Center drop - no split needed (handled at higher level)
                    return self
                }
                
                let newPane = SplitNode.pane(id: UUID(), tabId: newTabId)
                let existingPane = self
                
                let children: [SplitNode]
                switch zone.insertPosition {
                case .before:
                    children = [newPane, existingPane]
                case .after:
                    children = [existingPane, newPane]
                case .replace:
                    return self
                }
                
                return .split(
                    id: UUID(),
                    axis: axis,
                    children: children,
                    proportions: [0.5, 0.5]
                )
            }
            return self
            
        case .split(let id, let axis, let children, let proportions):
            // Recursively search children
            let newChildren = children.map { child in
                child.splitPane(paneId: paneId, newTabId: newTabId, zone: zone)
            }
            return .split(id: id, axis: axis, children: newChildren, proportions: proportions)
        }
    }
    
    /// Remove a pane from the tree, collapsing empty splits
    public func removePane(paneId: UUID) -> SplitNode? {
        switch self {
        case .pane(let id, _):
            return id == paneId ? nil : self
            
        case .split(let id, let axis, let children, let proportions):
            var newChildren: [SplitNode] = []
            var newProportions: [CGFloat] = []
            
            for (index, child) in children.enumerated() {
                if let remaining = child.removePane(paneId: paneId) {
                    newChildren.append(remaining)
                    newProportions.append(proportions[index])
                }
            }
            
            // Normalize proportions
            let total = newProportions.reduce(0, +)
            if total > 0 {
                newProportions = newProportions.map { $0 / total }
            }
            
            switch newChildren.count {
            case 0:
                return nil
            case 1:
                // Collapse single-child split
                return newChildren[0]
            default:
                return .split(id: id, axis: axis, children: newChildren, proportions: newProportions)
            }
        }
    }
}

// =============================================================================
// MARK: - Split Layout State
// =============================================================================

/// Observable state for the split layout
@Observable
@MainActor
public final class SplitLayoutState {
    
    /// Root node of the split tree
    public var root: SplitNode
    
    /// Currently active (focused) pane ID
    public var activePaneId: UUID?
    
    /// Current drop zone during drag
    public var currentDropZone: SplitDropZone?
    
    /// Pane ID being targeted for drop
    public var dropTargetPaneId: UUID?
    
    /// Tab ID being dragged
    public var draggingTabId: UUID?
    
    public init(initialTabId: UUID) {
        let paneId = UUID()
        self.root = .pane(id: paneId, tabId: initialTabId)
        self.activePaneId = paneId
    }
    
    /// Split a pane with a new tab
    public func splitPane(paneId: UUID, newTabId: UUID, zone: SplitDropZone) {
        root = root.splitPane(paneId: paneId, newTabId: newTabId, zone: zone)
    }
    
    /// Remove a pane from the layout
    public func removePane(paneId: UUID) {
        if let newRoot = root.removePane(paneId: paneId) {
            root = newRoot
            // Update active pane if needed
            if activePaneId == paneId {
                activePaneId = root.allTabIds.first.flatMap { root.findPane(tabId: $0) }
            }
        }
    }
    
    /// Clear drop state
    public func clearDropState() {
        currentDropZone = nil
        dropTargetPaneId = nil
        draggingTabId = nil
    }
}
