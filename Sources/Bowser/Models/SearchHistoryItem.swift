// SearchHistoryItem.swift - Search History Persistence
// Arc-style Command Bar search history using Codable + UserDefaults

import Foundation

// =============================================================================
// MARK: - Search History Item (Codable Model)
// =============================================================================

/// Represents a single search/navigation history entry for the Command Bar.
/// Uses Codable for JSON persistence to UserDefaults.
///
/// ## Usage
/// - Created when user submits a URL/search query in the Command Bar
/// - Displayed in reverse chronological order below the search field
/// - Supports filtering by query text for instant search suggestions
struct SearchHistoryItem: Identifiable, Codable, Equatable, Sendable {

    // MARK: - Properties

    /// Unique identifier for the history item
    let id: UUID

    /// The search query or URL entered by the user
    var text: String

    /// Timestamp when this entry was created/last used
    var timestamp: Date

    /// The resolved URL (if the text was converted to a URL)
    var resolvedURL: String?

    /// Whether this was a search query vs direct URL navigation
    var isSearchQuery: Bool

    /// Number of times this entry has been used (for ranking)
    var useCount: Int

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = Date(),
        resolvedURL: String? = nil,
        isSearchQuery: Bool = false,
        useCount: Int = 1
    ) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.resolvedURL = resolvedURL
        self.isSearchQuery = isSearchQuery
        self.useCount = useCount
    }

    // MARK: - Computed Properties

    /// Display text for the history list
    var displayText: String {
        text
    }

    /// Icon name based on entry type
    var iconName: String {
        if isSearchQuery {
            return "magnifyingglass"
        } else if let url = resolvedURL, url.hasPrefix("https://") {
            return "lock.fill"
        } else {
            return "globe"
        }
    }

    /// Domain extracted from resolved URL (for display)
    var domain: String? {
        guard let urlString = resolvedURL,
            let url = URL(string: urlString),
            let host = url.host
        else {
            return nil
        }
        return host
    }
}

// =============================================================================
// MARK: - Search History Store (Observable)
// =============================================================================

/// Observable store for search history using UserDefaults persistence.
/// Provides reactive updates to SwiftUI views.
@Observable
@MainActor
final class SearchHistoryStore {

    // MARK: - Singleton

    /// Shared instance for app-wide access
    static let shared = SearchHistoryStore()

    // MARK: - Properties

    /// All history items, sorted by timestamp (most recent first)
    private(set) var items: [SearchHistoryItem] = []

    /// UserDefaults key for persistence
    private let storageKey = "Bowser.SearchHistory"

    /// Maximum number of history items to retain
    var maxHistoryItems = 500

    // MARK: - Initialization

    private init() {
        loadFromStorage()
    }

    // MARK: - Public Methods

    /// Add or update a history entry
    /// - Parameters:
    ///   - text: The search query or URL text
    ///   - resolvedURL: The final URL navigated to
    ///   - isSearchQuery: Whether this was a search vs direct URL
    func addEntry(
        text: String,
        resolvedURL: String?,
        isSearchQuery: Bool
    ) {
        // Check for existing entry with same text
        if let existingIndex = items.firstIndex(where: { $0.text == text }) {
            // Update existing entry
            var existingItem = items[existingIndex]
            existingItem.timestamp = Date()
            existingItem.useCount += 1
            if let url = resolvedURL {
                existingItem.resolvedURL = url
            }

            // Move to front
            items.remove(at: existingIndex)
            items.insert(existingItem, at: 0)
        } else {
            // Create new entry
            let newItem = SearchHistoryItem(
                text: text,
                resolvedURL: resolvedURL,
                isSearchQuery: isSearchQuery
            )
            items.insert(newItem, at: 0)
        }

        // Prune old entries
        pruneOldEntries()

        // Persist changes
        saveToStorage()
    }

    /// Update an existing entry (e.g., when selected from history)
    func touchEntry(_ item: SearchHistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        var updatedItem = items[index]
        updatedItem.timestamp = Date()
        updatedItem.useCount += 1

        // Move to front
        items.remove(at: index)
        items.insert(updatedItem, at: 0)

        saveToStorage()
    }

    /// Delete a specific history entry
    func deleteEntry(_ item: SearchHistoryItem) {
        items.removeAll { $0.id == item.id }
        saveToStorage()
    }

    /// Clear all history
    func clearAll() {
        items.removeAll()
        saveToStorage()
    }

    /// Filter history by search text
    func filter(by searchText: String) -> [SearchHistoryItem] {
        guard !searchText.isEmpty else {
            return Array(items.prefix(10))
        }

        let lowercasedSearch = searchText.lowercased()
        return items.filter { item in
            item.text.lowercased().contains(lowercasedSearch)
                || (item.domain?.lowercased().contains(lowercasedSearch) ?? false)
        }.prefix(10).map { $0 }
    }

    // MARK: - Private Methods

    /// Load history from UserDefaults
    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            items = []
            return
        }

        do {
            let decoder = JSONDecoder()
            items = try decoder.decode([SearchHistoryItem].self, from: data)
            // Sort by timestamp (most recent first)
            items.sort { $0.timestamp > $1.timestamp }
        } catch {
            print("[SearchHistoryStore] Failed to load history: \(error)")
            items = []
        }
    }

    /// Save history to UserDefaults
    private func saveToStorage() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(items)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("[SearchHistoryStore] Failed to save history: \(error)")
        }
    }

    /// Remove entries older than the limit
    private func pruneOldEntries() {
        if items.count > maxHistoryItems {
            items = Array(items.prefix(maxHistoryItems))
        }
    }
}
