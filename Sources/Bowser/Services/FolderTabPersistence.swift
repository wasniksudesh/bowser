// FolderTabPersistence.swift - Per-folder tab serialization and persistence
// Stores each folder's tabs as JSON in ~/Library/Application Support/Bowser/Folders/{id}/tabs.json

import AppKit
import Foundation

// =============================================================================
// MARK: - Serialized Tab
// =============================================================================

/// Lightweight codable representation of a Tab for persistence.
/// Does not store favicon images (re-loaded on navigation) or CEF handles.
struct SerializedTab: Codable {
    let id: UUID
    let url: String
    let title: String
    let isPinned: Bool
    let parentTabId: UUID?

    init(from tab: Tab) {
        self.id = tab.id
        self.url = tab.url.absoluteString
        self.title = tab.title
        self.isPinned = tab.isPinned
        self.parentTabId = tab.parentTabId
    }

    func toTab() -> Tab {
        let url = URL(string: self.url) ?? URL(string: "https://www.google.com")!
        return Tab(
            id: id,
            parentTabId: parentTabId,
            url: url,
            title: title.isEmpty ? "New Tab" : title,
            isPinned: isPinned
        )
    }
}

// =============================================================================
// MARK: - Folder Tab Persistence
// =============================================================================

/// Manages saving and loading the tab list for each folder.
/// Each folder gets its own directory: ~/Library/Application Support/Bowser/Folders/{folderId}/
@MainActor
final class FolderTabPersistence {

    static let shared = FolderTabPersistence()

    private let foldersBaseDirectory: URL

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

    /// Save the current tabs for a folder
    func saveTabs(_ tabs: [Tab], forFolder folderId: UUID) {
        let dir = folderDirectory(for: folderId)
        ensureDirectory(dir)
        let fileURL = dir.appendingPathComponent("tabs.json")
        let serialized = tabs.map { SerializedTab(from: $0) }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(serialized)
            try data.write(to: fileURL, options: .atomic)
            print("[FolderTabPersistence] Saved \(tabs.count) tabs for folder \(folderId)")
        } catch {
            print("[FolderTabPersistence] Failed to save tabs for \(folderId): \(error)")
        }
    }

    /// Load persisted tabs for a folder. Returns nil if no tabs are saved yet.
    func loadTabs(forFolder folderId: UUID) -> [Tab]? {
        let fileURL = folderDirectory(for: folderId).appendingPathComponent("tabs.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let serialized = try JSONDecoder().decode([SerializedTab].self, from: data)
            let tabs = serialized.map { $0.toTab() }
            print("[FolderTabPersistence] Loaded \(tabs.count) tabs for folder \(folderId)")
            return tabs.isEmpty ? nil : tabs
        } catch {
            print("[FolderTabPersistence] Failed to load tabs for \(folderId): \(error)")
            return nil
        }
    }

    /// Delete all persisted data for a folder (called when folder is deleted)
    func deleteFolder(_ folderId: UUID) {
        let dir = folderDirectory(for: folderId)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Private

    private func folderDirectory(for folderId: UUID) -> URL {
        foldersBaseDirectory.appendingPathComponent(folderId.uuidString)
    }

    private func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
    }
}
