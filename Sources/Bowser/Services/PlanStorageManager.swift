//
//  PlanStorageManager.swift
//  Bowser
//
//  File-based storage manager for multiple plans
//

import Foundation

// =============================================================================
// MARK: - Plan Storage Manager
// =============================================================================

/// Manages file-based persistence for multiple plans.
/// Plans are stored in:
///   - Global: ~/Library/Application Support/Bowser/Plans/
///   - Per-folder: ~/Library/Application Support/Bowser/Folders/{folderId}/Plans/
@MainActor
final class PlanStorageManager {

    /// Shared singleton instance (global plans, no folder scope)
    static let shared = PlanStorageManager()

    /// Directory where plans are stored
    private let plansDirectory: URL

    /// Index file containing all plan metadata
    private let indexFileURL: URL

    /// Cached plan metadata for quick access
    private var cachedIndex: [PlanMetadata] = []

    // MARK: - Initialization

    /// Create the global shared instance (stored in Bowser/Plans/)
    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.plansDirectory = appSupport
            .appendingPathComponent("Bowser")
            .appendingPathComponent("Plans")
        self.indexFileURL = plansDirectory.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(
            at: plansDirectory,
            withIntermediateDirectories: true
        )
        loadIndex()
    }

    /// Create a folder-scoped instance (stored in Bowser/Folders/{folderId}/Plans/)
    init(folderId: UUID) {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.plansDirectory = appSupport
            .appendingPathComponent("Bowser")
            .appendingPathComponent("Folders")
            .appendingPathComponent(folderId.uuidString)
            .appendingPathComponent("Plans")
        self.indexFileURL = plansDirectory.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(
            at: plansDirectory,
            withIntermediateDirectories: true
        )
        loadIndex()
    }
    
    // MARK: - Public Methods
    
    /// Load all plan metadata from index
    /// - Returns: Array of plan metadata sorted by updatedAt (newest first)
    func loadAllPlans() -> [PlanMetadata] {
        return cachedIndex.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    /// Load a complete plan document
    /// - Parameter id: Plan UUID
    /// - Returns: Plan document or nil if not found
    func loadPlan(id: UUID) -> PlanDocument? {
        let fileURL = planFileURL(for: id)
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[PlanStorage] Plan file not found: \(id)")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let document = try JSONDecoder().decode(PlanDocument.self, from: data)
            return document
        } catch {
            print("[PlanStorage] Failed to load plan \(id): \(error)")
            return nil
        }
    }
    
    /// Save a plan document to disk
    /// - Parameter document: Plan document to save
    func savePlan(_ document: PlanDocument) {
        var updatedDocument = document
        updatedDocument.updateNodeCounts()
        
        let fileURL = planFileURL(for: updatedDocument.metadata.id)
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(updatedDocument)
            try data.write(to: fileURL, options: .atomic)
            
            // Update index
            updateIndexEntry(updatedDocument.metadata)
            
            print("[PlanStorage] Saved plan: \(updatedDocument.metadata.name)")
        } catch {
            print("[PlanStorage] Failed to save plan: \(error)")
        }
    }
    
    /// Delete a plan from disk
    /// - Parameter id: Plan UUID to delete
    func deletePlan(id: UUID) {
        let fileURL = planFileURL(for: id)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            
            // Remove from index
            cachedIndex.removeAll { $0.id == id }
            saveIndex()
            
            print("[PlanStorage] Deleted plan: \(id)")
        } catch {
            print("[PlanStorage] Failed to delete plan: \(error)")
        }
    }
    
    /// Fork an existing plan (create a copy)
    /// - Parameter sourceId: Source plan UUID
    /// - Returns: New plan document or nil if source not found
    func forkPlan(sourceId: UUID) -> PlanDocument? {
        guard let sourceDocument = loadPlan(id: sourceId) else {
            print("[PlanStorage] Cannot fork - source plan not found: \(sourceId)")
            return nil
        }
        
        // Create new plan with copied state
        let newId = UUID()
        let newMetadata = PlanMetadata(
            id: newId,
            name: "Copy of \(sourceDocument.metadata.name)",
            intent: sourceDocument.metadata.intent,
            createdAt: Date(),
            updatedAt: Date(),
            nodeCount: sourceDocument.metadata.nodeCount,
            completedNodeCount: sourceDocument.metadata.completedNodeCount
        )
        
        // Create new document with same state but new metadata
        let newDocument = PlanDocument(
            metadata: newMetadata,
            savedState: sourceDocument.savedState,
            clarificationQuestions: sourceDocument.clarificationQuestions,
            clarificationAnswers: sourceDocument.getClarificationAnswers()
        )
        
        // Save the forked plan
        savePlan(newDocument)
        
        print("[PlanStorage] Forked plan: \(sourceDocument.metadata.name) -> \(newMetadata.name)")
        return newDocument
    }
    
    /// Check if a plan exists
    /// - Parameter id: Plan UUID
    /// - Returns: True if plan file exists
    func planExists(id: UUID) -> Bool {
        let fileURL = planFileURL(for: id)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    // MARK: - Private Methods
    
    /// Get file URL for a plan
    private func planFileURL(for id: UUID) -> URL {
        plansDirectory.appendingPathComponent("\(id.uuidString).json")
    }
    
    /// Load index from disk
    private func loadIndex() {
        guard FileManager.default.fileExists(atPath: indexFileURL.path) else {
            cachedIndex = []
            return
        }
        
        do {
            let data = try Data(contentsOf: indexFileURL)
            cachedIndex = try JSONDecoder().decode([PlanMetadata].self, from: data)
            print("[PlanStorage] Loaded \(cachedIndex.count) plans from index")
        } catch {
            print("[PlanStorage] Failed to load index: \(error)")
            cachedIndex = []
            
            // Try to rebuild index from files
            rebuildIndex()
        }
    }
    
    /// Save index to disk
    private func saveIndex() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(cachedIndex)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            print("[PlanStorage] Failed to save index: \(error)")
        }
    }
    
    /// Update or add an entry in the index
    private func updateIndexEntry(_ metadata: PlanMetadata) {
        if let index = cachedIndex.firstIndex(where: { $0.id == metadata.id }) {
            cachedIndex[index] = metadata
        } else {
            cachedIndex.append(metadata)
        }
        saveIndex()
    }
    
    /// Rebuild index from plan files (recovery mechanism)
    private func rebuildIndex() {
        print("[PlanStorage] Rebuilding index from files...")
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: plansDirectory,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "json" && $0.lastPathComponent != "index.json" }
            
            var rebuiltIndex: [PlanMetadata] = []
            
            for fileURL in fileURLs {
                do {
                    let data = try Data(contentsOf: fileURL)
                    let document = try JSONDecoder().decode(PlanDocument.self, from: data)
                    rebuiltIndex.append(document.metadata)
                } catch {
                    print("[PlanStorage] Skipping corrupted file: \(fileURL.lastPathComponent)")
                }
            }
            
            cachedIndex = rebuiltIndex
            saveIndex()
            
            print("[PlanStorage] Rebuilt index with \(cachedIndex.count) plans")
        } catch {
            print("[PlanStorage] Failed to rebuild index: \(error)")
        }
    }
}
