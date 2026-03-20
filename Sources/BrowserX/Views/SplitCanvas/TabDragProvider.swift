// TabDragProvider.swift - Tab Drag & Drop Utilities
// Bowser - Swift 6.2
// Provides consistent drag operation setup for tabs across the app

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// =============================================================================
// MARK: - Tab Drag Item Provider
// =============================================================================

/// NSItemProvider subclass that provides tab ID for drag operations.
/// Used to initiate drag operations from SwiftUI with proper pasteboard types.
final class TabDragItemProvider: NSItemProvider {
    
    /// The tab ID being dragged
    let tabId: UUID
    
    /// Initialize with a tab ID
    init(tabId: UUID) {
        self.tabId = tabId
        super.init()
        
        // Register for multiple types for compatibility
        // 1. Custom tab ID type (preferred)
        registerDataRepresentation(forTypeIdentifier: UTType.bowserTabId.identifier, visibility: .all) { completion in
            let data = tabId.uuidString.data(using: .utf8) ?? Data()
            completion(data, nil)
            return nil
        }
        
        // 2. Plain text as fallback
        registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
            let data = tabId.uuidString.data(using: .utf8) ?? Data()
            completion(data, nil)
            return nil
        }
    }
}

// =============================================================================
// MARK: - UTType Extension
// =============================================================================

extension UTType {
    /// Custom type for tab IDs in drag operations
    static let bowserTabId = UTType(exportedAs: "com.bowser.tabId")
}

// =============================================================================
// MARK: - NSPasteboard Extension (Deprecated - use UTType instead)
// =============================================================================

extension NSPasteboard.PasteboardType {
    /// Custom pasteboard type for tab IDs (for AppKit)
    static let bowserTabId = NSPasteboard.PasteboardType("com.bowser.tabId")
}
