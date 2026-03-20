// TabDropDelegate.swift - Tab Drag & Drop Reordering
// Extracted from AppShellView for modularity and reuse

import SwiftUI

// =============================================================================
// MARK: - Tab Drop Delegate
// =============================================================================

/// Drop delegate for tab reordering via drag & drop.
/// Handles the logic for moving tabs when dropped on other tabs.
struct TabDropDelegate: DropDelegate {
    
    /// The target tab (where the dragged tab would be moved to)
    let tab: Tab
    
    /// Binding to the currently dragged tab
    @Binding var draggedTab: Tab?
    
    /// Browser state for performing the move operation
    let browserState: BrowserState
    
    func performDrop(info: DropInfo) -> Bool {
        draggedTab = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedTab,
              draggedTab.id != tab.id else {
            return
        }
        
        withAnimation(.default) {
            browserState.tabManager.moveTab(draggedTab.id, before: tab.id)
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
