// FolderHistoryPersistence.swift - Per-folder browsing history persistence
// Stores each folder's history as JSON in ~/Library/Application Support/Bowser/Folders/{id}/history.json

import Foundation
import SwiftUI

// =============================================================================
// MARK: - Global History Entry
// =============================================================================

/// A browsing history item annotated with its originating folder metadata.
/// Used by the homescreen global history sidebar to show cross-folder history.
struct GlobalHistoryEntry: Identifiable {
    let item: BrowsingHistoryItem
    let folderId: UUID
    let folderName: String
    let folderColor: Color
    let folderIcon: String

    var id: UUID { item.id }
}

// =============================================================================
// MARK: - Folder History Persistence
// =============================================================================

/// Manages saving and loading the browsing history for each folder.
/// Follows the same pattern as FolderTabPersistence.
@MainActor
final class FolderHistoryPersistence {

    static let shared = FolderHistoryPersistence()

    private let foldersBaseDirectory: URL

    /// Maximum history entries to retain per folder
    private let maxEntries = 1000

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.foldersBaseDirectory = appSupport
            .appendingPathComponent("Bowser")
            .appendingPathComponent("Folders")
    }

    // MARK: - Public API

    /// Add a new history entry for a folder.
    /// Deduplicates by URL (updates timestamp/title if same URL visited again).
    func addEntry(url: String, title: String, forFolder folderId: UUID) {
        guard !url.isEmpty,
              !url.hasPrefix("about:"),
              !url.hasPrefix("chrome-extension:")
        else { return }

        var items = loadHistory(forFolder: folderId)

        let newEntry = BrowsingHistoryItem(url: url, title: title)

        // Remove existing entry with same URL to move it to front
        items.removeAll { $0.url == url }

        // Insert at front (most recent first)
        items.insert(newEntry, at: 0)

        // Prune to max
        if items.count > maxEntries {
            items = Array(items.prefix(maxEntries))
        }

        saveHistory(items, forFolder: folderId)
    }

    /// Load browsing history for a folder (most recent first).
    func loadHistory(forFolder folderId: UUID) -> [BrowsingHistoryItem] {
        let fileURL = historyFile(for: folderId)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let items = try JSONDecoder().decode([BrowsingHistoryItem].self, from: data)
            return items
        } catch {
            print("[FolderHistoryPersistence] Failed to load history for \(folderId): \(error)")
            return []
        }
    }

    /// Replace the full history list for a folder (used after deletion).
    func saveFullHistory(_ items: [BrowsingHistoryItem], forFolder folderId: UUID) {
        saveHistory(items, forFolder: folderId)
    }

    /// Clear all browsing history for a folder.
    func clearHistory(forFolder folderId: UUID) {
        saveHistory([], forFolder: folderId)
    }

    /// Delete all data for a folder (called when folder is deleted).
    func deleteFolder(_ folderId: UUID) {
        let fileURL = historyFile(for: folderId)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Load browsing history across all folders, annotated with folder metadata.
    /// Returns entries sorted by timestamp (most recent first).
    func loadAllHistory(folders: [Folder]) -> [GlobalHistoryEntry] {
        var allEntries: [GlobalHistoryEntry] = []
        for folder in folders {
            let items = loadHistory(forFolder: folder.id)
            let entries = items.map { item in
                GlobalHistoryEntry(
                    item: item,
                    folderId: folder.id,
                    folderName: folder.name,
                    folderColor: folder.color,
                    folderIcon: folder.icon
                )
            }
            allEntries.append(contentsOf: entries)
        }
        allEntries.sort { $0.item.timestamp > $1.item.timestamp }
        return allEntries
    }

    // MARK: - Private

    private func historyFile(for folderId: UUID) -> URL {
        foldersBaseDirectory
            .appendingPathComponent(folderId.uuidString)
            .appendingPathComponent("history.json")
    }

    private func saveHistory(_ items: [BrowsingHistoryItem], forFolder folderId: UUID) {
        let dir = foldersBaseDirectory.appendingPathComponent(folderId.uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("history.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[FolderHistoryPersistence] Failed to save history for \(folderId): \(error)")
        }
    }
}
