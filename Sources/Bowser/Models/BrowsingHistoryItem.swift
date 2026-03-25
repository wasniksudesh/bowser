// BrowsingHistoryItem.swift - Per-folder browsing history model

import Foundation

// =============================================================================
// MARK: - Browsing History Item
// =============================================================================

/// A single entry in a folder's browsing history.
/// Recorded each time the user navigates to a URL within a folder.
struct BrowsingHistoryItem: Identifiable, Codable, Equatable {

    let id: UUID
    var url: String
    var title: String
    var timestamp: Date
    var domain: String?

    init(
        id: UUID = UUID(),
        url: String,
        title: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.title = title.isEmpty ? url : title
        self.timestamp = timestamp
        self.domain = URL(string: url)?.host
    }

    /// Display title — falls back to domain then raw URL
    var displayTitle: String {
        if !title.isEmpty && title != url { return title }
        return domain ?? url
    }

    /// Favicon SF Symbol based on URL scheme
    var iconName: String {
        if url.hasPrefix("https://") { return "lock.fill" }
        if url.hasPrefix("http://") { return "globe" }
        return "doc.text"
    }
}
