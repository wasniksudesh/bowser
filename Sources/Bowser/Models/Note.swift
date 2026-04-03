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
    var isTimeline: Bool
    /// Non-nil when this note was generated from a meeting recording.
    var meetingMetadata: MeetingMetadata?

    init(
        id: UUID = UUID(),
        title: String = "Untitled Note",
        contentRTFD: Data = Data(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isTimeline: Bool = false,
        meetingMetadata: MeetingMetadata? = nil
    ) {
        self.id = id
        self.title = title
        self.contentRTFD = contentRTFD
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isTimeline = isTimeline
        self.meetingMetadata = meetingMetadata
    }

    // Custom Codable to handle backward compatibility with notes saved before
    // the isTimeline / meetingMetadata fields existed.
    enum CodingKeys: String, CodingKey {
        case id, title, contentRTFD, createdAt, updatedAt, isTimeline, meetingMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        contentRTFD = try container.decode(Data.self, forKey: .contentRTFD)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isTimeline = try container.decodeIfPresent(Bool.self, forKey: .isTimeline) ?? false
        meetingMetadata = try container.decodeIfPresent(MeetingMetadata.self, forKey: .meetingMetadata)
    }

    /// Deterministic UUID for a folder's timeline note, derived from the folder ID.
    static func timelineNoteId(forFolder folderId: UUID) -> UUID {
        var bytes = Array(folderId.uuidString.utf8)
        bytes.append(contentsOf: "timeline".utf8)
        var hash: [UInt8] = Array(repeating: 0, count: 16)
        for (i, byte) in bytes.enumerated() {
            hash[i % 16] ^= byte &+ UInt8(i % 251)
        }
        hash[6] = (hash[6] & 0x0F) | 0x40 // version 4
        hash[8] = (hash[8] & 0x3F) | 0x80 // variant 1
        return UUID(uuid: (hash[0], hash[1], hash[2], hash[3],
                           hash[4], hash[5], hash[6], hash[7],
                           hash[8], hash[9], hash[10], hash[11],
                           hash[12], hash[13], hash[14], hash[15]))
    }
}
