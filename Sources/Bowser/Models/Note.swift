// Note.swift - Rich text note model
// Stored as RTFD data (supports formatted text, images, and hyperlinks)

import Foundation

// =============================================================================
// MARK: - Note Model
// =============================================================================

/// A rich-text note stored per folder alongside tabs and plans.
/// Content is serialized as RTFD data from NSAttributedString, which natively
/// supports bold, italic, headings, images, and hyperlinks.
struct Note: Identifiable, Codable {
    let id: UUID
    var title: String
    var contentRTFD: Data
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "Untitled Note",
        contentRTFD: Data = Data(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.contentRTFD = contentRTFD
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
