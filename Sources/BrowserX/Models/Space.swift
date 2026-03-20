// Space.swift - Arc-Style Workspace Model
// Represents a workspace/space for organizing tabs (Arc-style)

import Foundation
import SwiftUI

// =============================================================================
// MARK: - Space Model (Sendable)
// =============================================================================

/// Represents an Arc-style workspace/space for organizing tabs
/// Each space can have its own set of tabs, color theme, and name
struct Space: Identifiable, Equatable, Sendable, Codable {
    
    // MARK: - Properties
    
    /// Unique identifier for this space
    let id: UUID
    
    /// Display name for the space
    var name: String
    
    /// Theme color for the space
    var color: Color
    
    /// Tab IDs belonging to this space
    var tabIds: [UUID]
    
    // MARK: - Computed Properties
    
    /// Number of tabs in this space
    var tabCount: Int {
        tabIds.count
    }
    
    /// Whether this space has any tabs
    var hasTabs: Bool {
        !tabIds.isEmpty
    }
    
    /// First letter for icon display
    var iconLetter: String {
        String(name.prefix(1)).uppercased()
    }
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        name: String,
        color: Color = .blue,
        tabIds: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.tabIds = tabIds
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, name, color, tabIds
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decode(Color.self, forKey: .color)
        tabIds = try container.decodeIfPresent([UUID].self, forKey: .tabIds) ?? []
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
        try container.encode(tabIds, forKey: .tabIds)
    }
}

// =============================================================================
// MARK: - Space Defaults
// =============================================================================

extension Space {
    /// Default space when none exist
    static var defaultSpace: Space {
        Space(name: "Personal", color: .blue)
    }
    
    /// Default spaces for new users
    static var defaults: [Space] {
        [
            Space(name: "Personal", color: .blue),
            Space(name: "Work", color: .purple),
            Space(name: "Research", color: .green)
        ]
    }
    
    /// Available colors for space customization
    static var availableColors: [Color] {
        [.blue, .purple, .green, .orange, .pink, .cyan, .indigo, .red, .yellow, .teal]
    }
}
