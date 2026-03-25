// NotePersistence.swift - Per-folder note serialization and persistence
// Stores each folder's notes as JSON in ~/Library/Application Support/Bowser/Folders/{id}/Notes/

import Foundation

// =============================================================================
// MARK: - Note Persistence
// =============================================================================

/// Manages saving and loading rich-text notes for each folder.
/// Storage layout: ~/Library/Application Support/Bowser/Folders/{folderId}/Notes/{noteId}.json
/// An index.json caches metadata for fast listing without loading every note.
@MainActor
final class NotePersistence {

    static let shared = NotePersistence()

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

    /// Save a note to disk (creates or updates).
    func saveNote(_ note: Note, forFolder folderId: UUID) {
        let dir = notesDirectory(for: folderId)
        ensureDirectory(dir)

        let fileURL = dir.appendingPathComponent("\(note.id.uuidString).json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(note)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("[NotePersistence] Failed to save note \(note.id): \(error)")
        }

        updateIndex(forFolder: folderId)
    }

    /// Load a single note by ID.
    func loadNote(id noteId: UUID, forFolder folderId: UUID) -> Note? {
        let fileURL = notesDirectory(for: folderId)
            .appendingPathComponent("\(noteId.uuidString).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Note.self, from: data)
        } catch {
            print("[NotePersistence] Failed to load note \(noteId): \(error)")
            return nil
        }
    }

    /// Load all notes for a folder (metadata from index, full content on demand).
    func loadAllNotes(forFolder folderId: UUID) -> [Note] {
        let dir = notesDirectory(for: folderId)
        let indexURL = dir.appendingPathComponent("index.json")

        if FileManager.default.fileExists(atPath: indexURL.path) {
            do {
                let data = try Data(contentsOf: indexURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode([Note].self, from: data)
            } catch {
                print("[NotePersistence] Index decode failed, rebuilding: \(error)")
            }
        }

        return rebuildIndex(forFolder: folderId)
    }

    /// Delete a note from disk. Timeline notes cannot be deleted.
    func deleteNote(id noteId: UUID, forFolder folderId: UUID) {
        if let note = loadNote(id: noteId, forFolder: folderId), note.isTimeline {
            print("[NotePersistence] Cannot delete timeline note \(noteId)")
            return
        }
        let fileURL = notesDirectory(for: folderId)
            .appendingPathComponent("\(noteId.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
        updateIndex(forFolder: folderId)
    }

    // MARK: - Private Helpers

    private func notesDirectory(for folderId: UUID) -> URL {
        foldersBaseDirectory
            .appendingPathComponent(folderId.uuidString)
            .appendingPathComponent("Notes")
    }

    private func ensureDirectory(_ url: URL) {
        try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)
    }

    /// Rebuild the index by scanning individual note files.
    @discardableResult
    private func rebuildIndex(forFolder folderId: UUID) -> [Note] {
        let dir = notesDirectory(for: folderId)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)
        else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var notes: [Note] = []

        for file in files where file.pathExtension == "json" && file.lastPathComponent != "index.json" {
            if let data = try? Data(contentsOf: file),
               let note = try? decoder.decode(Note.self, from: data)
            {
                notes.append(note)
            }
        }

        notes.sort { $0.updatedAt > $1.updatedAt }
        writeIndex(notes, forFolder: folderId)
        return notes
    }

    /// Rewrite the index.json from current note files.
    private func updateIndex(forFolder folderId: UUID) {
        rebuildIndex(forFolder: folderId)
    }

    private func writeIndex(_ notes: [Note], forFolder folderId: UUID) {
        let dir = notesDirectory(for: folderId)
        ensureDirectory(dir)
        let indexURL = dir.appendingPathComponent("index.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(notes)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            print("[NotePersistence] Failed to write index: \(error)")
        }
    }
}
