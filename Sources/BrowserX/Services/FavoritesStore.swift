// FavoritesStore.swift - Favorites/Bookmarks Management
// Observable store for managing favorites with persistence handler pattern

import Foundation
import SwiftUI

// =============================================================================
// MARK: - Favorites Store (Observable)
// =============================================================================

/// Dedicated manager for favorites/bookmarks
/// Uses a persistence handler pattern for app-level storage integration
/// Independently testable and free from direct UserDefaults coupling
@Observable
@MainActor
final class FavoritesStore {
    
    // MARK: - Properties
    
    /// All user favorites
    private(set) var favorites: [Favorite] = []
    
    /// Maximum items to show in the sidebar grid
    let maxGridItems: Int
    
    /// Handler called when favorites change (for persistence)
    /// The app layer provides this to save data to UserDefaults or other storage
    var persistenceHandler: ((Data) -> Void)?
    
    /// Handler called to load initial data
    /// The app layer provides this to load data from UserDefaults or other storage
    var loadHandler: (() -> Data?)?
    
    // MARK: - Computed Properties
    
    /// Favorites limited for grid display
    var gridFavorites: [Favorite] {
        Array(favorites.prefix(maxGridItems))
    }
    
    /// Whether the favorites list is empty
    var isEmpty: Bool {
        favorites.isEmpty
    }
    
    /// Total count of favorites
    var count: Int {
        favorites.count
    }
    
    // MARK: - Initialization
    
    /// Initialize with optional max grid items and default favorites
    init(
        maxGridItems: Int = 12,
        defaults: [Favorite]? = nil,
        persistenceHandler: ((Data) -> Void)? = nil,
        loadHandler: (() -> Data?)? = nil
    ) {
        self.maxGridItems = maxGridItems
        self.persistenceHandler = persistenceHandler
        self.loadHandler = loadHandler
        
        // Load from handler or use defaults
        if let loadHandler, let data = loadHandler() {
            do {
                self.favorites = try JSONDecoder().decode([Favorite].self, from: data)
            } catch {
                self.favorites = defaults ?? Favorite.defaults
            }
        } else {
            self.favorites = defaults ?? Favorite.defaults
        }
    }
    
    // MARK: - CRUD Operations
    
    /// Add a new favorite
    func add(_ favorite: Favorite) {
        favorites.append(favorite)
        persistChanges()
    }
    
    /// Add a favorite from page details
    func addFromPage(url: URL, title: String, favicon: Data? = nil) {
        let favorite = Favorite(
            title: title.isEmpty ? url.host ?? "Untitled" : title,
            url: url,
            favicon: favicon,
            color: .randomPastel
        )
        add(favorite)
    }
    
    /// Remove a favorite
    func remove(_ favorite: Favorite) {
        remove(id: favorite.id)
    }
    
    /// Remove a favorite by ID
    func remove(id: UUID) {
        favorites.removeAll { $0.id == id }
        persistChanges()
    }
    
    /// Update an existing favorite
    func update(_ favorite: Favorite) {
        guard let index = favorites.firstIndex(where: { $0.id == favorite.id }) else {
            return
        }
        favorites[index] = favorite
        persistChanges()
    }
    
    /// Move a favorite from one position to another (for reordering)
    func move(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        persistChanges()
    }
    
    /// Check if a URL is already favorited
    func contains(url: URL) -> Bool {
        favorites.contains { $0.url == url }
    }
    
    /// Find a favorite by URL
    func favorite(for url: URL) -> Favorite? {
        favorites.first { $0.url == url }
    }
    
    /// Find a favorite by ID
    func favorite(for id: UUID) -> Favorite? {
        favorites.first { $0.id == id }
    }
    
    // MARK: - Bulk Operations
    
    /// Replace all favorites (useful for sync/import)
    func setFavorites(_ newFavorites: [Favorite]) {
        favorites = newFavorites
        persistChanges()
    }
    
    /// Reset to default favorites
    func resetToDefaults() {
        favorites = Favorite.defaults
        persistChanges()
    }
    
    /// Clear all favorites
    func clear() {
        favorites = []
        persistChanges()
    }
    
    // MARK: - Persistence
    
    /// Encode and persist favorites via handler
    private func persistChanges() {
        guard let handler = persistenceHandler else { return }
        do {
            let data = try JSONEncoder().encode(favorites)
            handler(data)
        } catch {
            // Silently fail - logging should be handled at app level
        }
    }
    
    /// Load favorites from external data
    func load(from data: Data) {
        do {
            let decoded = try JSONDecoder().decode([Favorite].self, from: data)
            favorites = decoded
        } catch {
            // Keep existing favorites on decode failure
        }
    }
    
    /// Export favorites as encoded data
    func export() -> Data? {
        try? JSONEncoder().encode(favorites)
    }
}
