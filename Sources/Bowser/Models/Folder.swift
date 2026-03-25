// Folder.swift - Desktop-style folder model for organizing browser sessions
// Evolved from Space.swift - each folder owns its own tabs, plans, and agents

import Foundation
import SwiftUI

// =============================================================================
// MARK: - Folder Model
// =============================================================================

/// Represents a project folder on the homescreen desktop.
/// Each folder owns its own set of tabs, plans, and agent sessions.
struct Folder: Identifiable, Equatable, Sendable, Codable {

    // MARK: - Well-Known IDs

    /// Stable UUID for the "misc" folder so it survives across launches
    static let miscId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    // MARK: - Properties

    let id: UUID
    var name: String
    var color: Color
    var icon: String      // SF Symbol name, default "folder.fill"
    var createdAt: Date
    var gridIndex: Int    // ordering in the auto-layout grid

    // MARK: - Computed Properties

    var isMisc: Bool { id == Self.miscId }

    var iconLetter: String {
        String(name.prefix(1)).uppercased()
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        name: String,
        color: Color = .blue,
        icon: String = "folder.fill",
        createdAt: Date = Date(),
        gridIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.createdAt = createdAt
        self.gridIndex = gridIndex
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, color, icon, createdAt, gridIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decode(Color.self, forKey: .color)
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "folder.fill"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        gridIndex = try container.decodeIfPresent(Int.self, forKey: .gridIndex) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
        try container.encode(icon, forKey: .icon)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(gridIndex, forKey: .gridIndex)
    }
}

// =============================================================================
// MARK: - Folder Defaults
// =============================================================================

extension Folder {

    static var availableColors: [Color] {
        [.blue, .purple, .green, .orange, .pink, .cyan, .indigo, .red, .yellow, .teal]
    }

    /// The permanent misc folder — always exists, cannot be deleted or renamed.
    /// Uses gridIndex 0; actual sort order is enforced by FolderManager.sortedFolders.
    static var misc: Folder {
        Folder(
            id: miscId,
            name: "misc",
            color: .gray,
            icon: "tray.fill",
            gridIndex: 0
        )
    }

    /// Default folders shown to new users, matching the homescreen mockup
    static var defaults: [Folder] {
        let items: [(name: String, color: Color, icon: String)] = [
            ("Project-A",  .blue,   "doc.text.fill"),
            ("Task-XYZ",   .purple, "checkmark.circle.fill"),
            ("Trip",       .green,  "airplane"),
            ("Homework",   .orange, "book.fill"),
            ("Jira-1",     .pink,   "tray.fill"),
            ("Inc-123",    .cyan,   "number.circle.fill"),
        ]
        var folders = items.enumerated().map { index, item in
            Folder(
                name: item.name,
                color: item.color,
                icon: item.icon,
                gridIndex: index
            )
        }
        folders.append(misc)
        return folders
    }
}
