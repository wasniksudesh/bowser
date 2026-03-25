// FolderManager.swift - Desktop folder management service
// Evolved from SpacesManager.swift - manages folders that each own tabs/plans/agents

import Foundation
import SwiftUI

// =============================================================================
// MARK: - Folder Manager (Observable)
// =============================================================================

/// Manages the collection of project folders shown on the homescreen desktop.
/// Persists folder metadata to UserDefaults; per-folder tabs are handled by FolderTabPersistence.
@Observable
@MainActor
final class FolderManager {

    // MARK: - Properties

    private(set) var folders: [Folder] = []

    var persistenceHandler: ((Data) -> Void)?
    var loadHandler: (() -> Data?)?

    // MARK: - Computed Properties

    /// Sorted folders — misc always appears last
    var sortedFolders: [Folder] {
        folders.sorted { a, b in
            if a.isMisc { return false }
            if b.isMisc { return true }
            return a.gridIndex < b.gridIndex
        }
    }

    var miscFolder: Folder {
        folders.first(where: { $0.isMisc }) ?? Folder.misc
    }

    var count: Int { folders.count }

    // MARK: - Initialization

    init(
        persistenceHandler: ((Data) -> Void)? = nil,
        loadHandler: (() -> Data?)? = nil
    ) {
        self.persistenceHandler = persistenceHandler
        self.loadHandler = loadHandler
        loadFolders()
    }

    // MARK: - Loading

    private func loadFolders() {
        if let handler = loadHandler, let data = handler() {
            do {
                let decoded = try JSONDecoder().decode([Folder].self, from: data)
                folders = decoded.isEmpty ? Folder.defaults : decoded
            } catch {
                folders = Folder.defaults
            }
        } else {
            folders = Folder.defaults
        }
        ensureMiscFolder()
    }

    /// Guarantees the misc folder always exists
    private func ensureMiscFolder() {
        guard !folders.contains(where: { $0.isMisc }) else { return }
        folders.append(Folder.misc)
        persist()
    }

    // MARK: - CRUD

    /// Create a new folder and append it to the grid
    @discardableResult
    func createFolder(name: String, color: Color? = nil) -> Folder {
        let nextIndex = nextGridIndex()
        let folderColor = color ?? Self.randomColor
        let folder = Folder(
            name: name,
            color: folderColor,
            gridIndex: nextIndex
        )
        folders.append(folder)
        persist()
        return folder
    }

    /// Rename a folder (misc folder cannot be renamed)
    func rename(_ folder: Folder, to newName: String) {
        guard !folder.isMisc else { return }
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[index].name = newName
        persist()
    }

    /// Change a folder's color
    func setColor(_ folder: Folder, to color: Color) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[index].color = color
        persist()
    }

    /// Delete a folder (misc folder cannot be deleted)
    func delete(_ folder: Folder) {
        guard !folder.isMisc else { return }
        folders.removeAll { $0.id == folder.id }
        reindexGrid()
        persist()
    }

    /// Delete a folder by ID (misc folder cannot be deleted)
    func delete(id: UUID) {
        guard id != Folder.miscId else { return }
        folders.removeAll { $0.id == id }
        reindexGrid()
        persist()
    }

    /// Duplicate a folder and all its persisted tabs
    @discardableResult
    func copyFolder(_ source: Folder) -> Folder {
        let nextIndex = nextGridIndex()
        let copy = Folder(
            name: "\(source.name) copy",
            color: source.color,
            icon: source.icon,
            gridIndex: nextIndex
        )
        folders.append(copy)
        persist()

        // Copy persisted tabs
        let persistence = FolderTabPersistence.shared
        if let sourceTabs = persistence.loadTabs(forFolder: source.id) {
            let duplicatedTabs = sourceTabs.map { original in
                Tab(url: original.url, title: original.title, isPinned: original.isPinned)
            }
            persistence.saveTabs(duplicatedTabs, forFolder: copy.id)
        }

        return copy
    }

    /// Reorder folder from one grid position to another
    func reorderFolder(from sourceIndex: Int, to destinationIndex: Int) {
        guard folders.indices.contains(sourceIndex),
              folders.indices.contains(destinationIndex) else { return }
        var sorted = sortedFolders
        let item = sorted.remove(at: sourceIndex)
        sorted.insert(item, at: destinationIndex)
        for (i, folder) in sorted.enumerated() {
            if let idx = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[idx].gridIndex = i
            }
        }
        persist()
    }

    /// Look up a folder by ID
    func folder(for id: UUID) -> Folder? {
        folders.first { $0.id == id }
    }

    // MARK: - Persistence

    private func reindexGrid() {
        let sorted = folders.sorted { $0.gridIndex < $1.gridIndex }
        for (i, folder) in sorted.enumerated() {
            if let idx = folders.firstIndex(where: { $0.id == folder.id }) {
                folders[idx].gridIndex = i
            }
        }
    }

    func persist() {
        guard let handler = persistenceHandler else { return }
        do {
            let data = try JSONEncoder().encode(folders)
            handler(data)
        } catch {
            print("[FolderManager] Failed to persist folders: \(error)")
        }
    }

    // MARK: - Helpers

    /// Next available gridIndex (excludes misc so we never overflow)
    private func nextGridIndex() -> Int {
        let nonMisc = folders.filter { !$0.isMisc }
        return (nonMisc.map(\.gridIndex).max() ?? -1) + 1
    }

    private static var randomColor: Color {
        Folder.availableColors.randomElement() ?? .blue
    }
}
