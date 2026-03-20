// Favorite.swift - Bookmarked Site Model
// Represents a favorited/bookmarked site for quick access

import Foundation
import SwiftUI

// =============================================================================
// MARK: - Favorite Model (Sendable)
// =============================================================================

/// Represents a favorited/bookmarked site for the favorites grid
/// Pure data model with Codable support for persistence
struct Favorite: Identifiable, Equatable, Sendable, Codable {
    
    // MARK: - Properties
    
    /// Unique identifier for this favorite
    let id: UUID
    
    /// Display title for the favorite
    var title: String
    
    /// URL of the favorited site
    var url: URL
    
    /// Favicon data (PNG/ICO bytes)
    var favicon: Data?
    
    /// Color for the favorite icon background/letter
    var color: Color
    
    // MARK: - Computed Properties
    
    /// First letter of the title for avatar fallback
    var letter: String {
        String(title.prefix(1)).uppercased()
    }
    
    /// Alias for letter (used in icon display)
    var iconLetter: String {
        letter
    }
    
    /// Domain for display purposes
    var displayDomain: String {
        guard let host = url.host else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        favicon: Data? = nil,
        color: Color = .blue
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.favicon = favicon
        self.color = color
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, title, url, favicon, color
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(URL.self, forKey: .url)
        favicon = try container.decodeIfPresent(Data.self, forKey: .favicon)
        color = try container.decode(Color.self, forKey: .color)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(favicon, forKey: .favicon)
        try container.encode(color, forKey: .color)
    }
}

// =============================================================================
// MARK: - Favorite Defaults
// =============================================================================

extension Favorite {
    /// Default favorites for new users
    static var defaults: [Favorite] {
        [
            Favorite(title: "Google", url: URL(string: "https://www.google.com")!, color: .blue),
            Favorite(title: "GitHub", url: URL(string: "https://github.com")!, color: .gray),
            Favorite(title: "Twitter", url: URL(string: "https://twitter.com")!, color: .cyan),
            Favorite(title: "YouTube", url: URL(string: "https://www.youtube.com")!, color: .red),
        ]
    }
}

// =============================================================================
// MARK: - Color Extensions (for Codable)
// =============================================================================

extension Color: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case red, green, blue, opacity
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let red = try container.decode(Double.self, forKey: .red)
        let green = try container.decode(Double.self, forKey: .green)
        let blue = try container.decode(Double.self, forKey: .blue)
        let opacity = try container.decode(Double.self, forKey: .opacity)
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Extract color components using resolved color
        // Note: This works for standard SwiftUI colors
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var opacity: CGFloat = 0
        
        #if canImport(AppKit)
        if let nsColor = NSColor(self).usingColorSpace(.sRGB) {
            red = nsColor.redComponent
            green = nsColor.greenComponent
            blue = nsColor.blueComponent
            opacity = nsColor.alphaComponent
        }
        #endif
        
        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
        try container.encode(opacity, forKey: .opacity)
    }
}

// =============================================================================
// MARK: - Color Utilities
// =============================================================================

extension Color {
    /// Random pastel color for new favorites
    static var randomPastel: Color {
        let colors: [Color] = [
            .blue.opacity(0.7),
            .purple.opacity(0.7),
            .green.opacity(0.7),
            .orange.opacity(0.7),
            .pink.opacity(0.7),
            .cyan.opacity(0.7),
            .indigo.opacity(0.7),
            .mint.opacity(0.7),
            .teal.opacity(0.7)
        ]
        return colors.randomElement() ?? .blue
    }
}
