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

    var sortedFolders: [Folder] {
        folders.sorted { $0.gridIndex < $1.gridIndex }
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
    }

    // MARK: - CRUD

    /// Create a new folder and append it to the grid
    @discardableResult
    func createFolder(name: String, color: Color? = nil) -> Folder {
        let nextIndex = (folders.map(\.gridIndex).max() ?? -1) + 1
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

    /// Rename a folder
    func rename(_ folder: Folder, to newName: String) {
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

    /// Delete a folder
    func delete(_ folder: Folder) {
        folders.removeAll { $0.id == folder.id }
        reindexGrid()
        persist()
    }

    /// Delete a folder by ID
    func delete(id: UUID) {
        folders.removeAll { $0.id == id }
        reindexGrid()
        persist()
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

    private static var randomColor: Color {
        Folder.availableColors.randomElement() ?? .blue
    }
}
