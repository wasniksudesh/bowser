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
    let tabType: String?
    let noteId: UUID?

    init(from tab: Tab) {
        self.id = tab.id
        self.url = tab.url.absoluteString
        self.title = tab.title
        self.isPinned = tab.isPinned
        self.parentTabId = tab.parentTabId
        self.tabType = tab.tabType == .web ? nil : tab.tabType.rawValue
        self.noteId = tab.noteId
    }

    func toTab() -> Tab {
        let url = URL(string: self.url) ?? URL(string: "https://www.google.com")!
        let resolvedTabType = tabType.flatMap { TabType(rawValue: $0) } ?? .web
        return Tab(
            id: id,
            parentTabId: parentTabId,
            url: url,
            title: title.isEmpty ? "New Tab" : title,
            isPinned: isPinned,
            tabType: resolvedTabType,
            noteId: noteId
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

    /// Search all given folders for a tab whose URL host matches the target host.
    /// Returns (folderId, tab) of the first match, or nil.
    func findTab(matchingHost host: String, inFolders folderIds: [UUID]) -> (folderId: UUID, tab: Tab)? {
        let lowered = host.lowercased()
        for fid in folderIds {
            guard let tabs = loadTabs(forFolder: fid) else { continue }
            if let match = tabs.first(where: {
                $0.url.host?.lowercased().contains(lowered) == true
            }) {
                return (fid, match)
            }
        }
        return nil
    }

    /// Append a single tab to a folder's persisted tabs and save
    func appendTab(_ tab: Tab, toFolder folderId: UUID) {
        var tabs = loadTabs(forFolder: folderId) ?? []
        tabs.append(tab)
        saveTabs(tabs, forFolder: folderId)
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
