// PageLifecycleManager.swift - Manages Page Lifecycle States
// Handles freeze/hibernate/alive tiers for stacked pages

import Foundation
import AppKit

// =============================================================================
// MARK: - Page Lifecycle Manager
// =============================================================================

/// Manages lifecycle states for pages in a stack
/// Implements tiered suspension: Frozen (oldest 30%), Hibernating (31-60%), Alive (remainder)
@MainActor
final class PageLifecycleManager {
    
    // MARK: - Lifecycle Calculation
    
    /// Calculate lifecycle states for all pages in a stack
    /// - Parameters:
    ///   - pages: Array of pages in the stack
    ///   - activeIndex: Index of the currently active page
    ///   - visitedIndices: Set of indices that have been visited in this session
    /// - Returns: Array of lifecycle states corresponding to each page
    static func calculateLifecycleStates(
        pages: [Page],
        activeIndex: Int,
        visitedIndices: Set<Int>
    ) -> [PageLifecycleState] {
        guard !pages.isEmpty else { return [] }
        
        var states: [PageLifecycleState] = Array(repeating: .alive, count: pages.count)
        
        // Active page is always alive
        if pages.indices.contains(activeIndex) {
            states[activeIndex] = .alive
        }
        
        // Calculate tier boundaries based on total page count
        let totalPages = pages.count
        let frozenCount = Int(ceil(Double(totalPages) * StackConstants.frozenTierPercentage))
        let hibernatingCount = Int(ceil(Double(totalPages) * (StackConstants.hibernatingTierEnd - StackConstants.hibernatingTierStart)))
        
        // Sort pages by age (oldest first), excluding starred and active
        let sortedIndices = pages.indices
            .filter { $0 != activeIndex && !pages[$0].isStarred }
            .sorted { pages[$0].lastVisitedAt < pages[$1].lastVisitedAt }
        
        // Apply frozen state to oldest 30%
        for i in 0..<min(frozenCount, sortedIndices.count) {
            let index = sortedIndices[i]
            states[index] = .frozen
        }
        
        // Apply hibernating state to next batch (31-60% range) if not visited in current session
        let hibernatingStart = frozenCount
        let hibernatingEnd = min(hibernatingStart + hibernatingCount, sortedIndices.count)
        for i in hibernatingStart..<hibernatingEnd {
            guard i < sortedIndices.count else { break }
            let index = sortedIndices[i]
            
            // Only hibernate if not visited in this session
            if !visitedIndices.contains(index) {
                states[index] = .hibernating
            }
        }
        
        return states
    }
    
    /// Update lifecycle states for pages in a tab
    /// - Parameters:
    ///   - tab: The tab containing the pages
    ///   - visitedIndices: Set of page indices visited in current session
    /// - Returns: Updated tab with new lifecycle states
    static func updateLifecycleStates(
        for tab: inout Tab,
        visitedIndices: Set<Int>
    ) {
        guard tab.stackModeEnabled else { return }
        
        let states = calculateLifecycleStates(
            pages: tab.pages,
            activeIndex: tab.activePageIndex,
            visitedIndices: visitedIndices
        )
        
        for (index, state) in states.enumerated() {
            guard tab.pages.indices.contains(index) else { continue }
            tab.pages[index].lifecycleState = state
        }
    }
    
    // MARK: - Page Limit Enforcement
    
    /// Enforce 7-page limit by removing oldest non-starred page
    /// - Parameter pages: Array of pages to trim
    /// - Returns: Tuple of (trimmed pages, removed page index if any)
    static func enforcePageLimit(_ pages: [Page]) -> (pages: [Page], removedIndex: Int?) {
        // Count non-starred pages
        let nonStarredCount = pages.filter { !$0.isStarred }.count
        
        guard nonStarredCount > StackConstants.maxPages else {
            return (pages, nil)
        }
        
        // Find oldest non-starred page
        var oldestIndex: Int?
        var oldestDate = Date()
        
        for (index, page) in pages.enumerated() {
            if !page.isStarred && page.lastVisitedAt < oldestDate {
                oldestDate = page.lastVisitedAt
                oldestIndex = index
            }
        }
        
        guard let indexToRemove = oldestIndex else {
            return (pages, nil)
        }
        
        var trimmedPages = pages
        trimmedPages.remove(at: indexToRemove)
        
        return (trimmedPages, indexToRemove)
    }
    
    // MARK: - Snapshot Management
    
    /// Capture snapshot for a page before suspending
    /// - Parameters:
    ///   - browserId: The browser ID (page's browserId) to capture
    ///   - pageId: The page ID to capture (for reference)
    ///   - completion: Called with the captured snapshot
    static func capturePageSnapshot(
        browserId: UUID,
        pageId: UUID,
        completion: @escaping @MainActor (NSImage?) -> Void
    ) {
        // Use BrowserManager to capture snapshot from the CEF browser using browserId
        BrowserManager.shared.captureSnapshot(pageId: browserId, completion: completion)
    }
}
