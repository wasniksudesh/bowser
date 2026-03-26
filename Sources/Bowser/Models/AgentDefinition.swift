//
//  AgentDefinition.swift
//  Bowser
//
//  Persisted agent definition for widget re-execution
//  Contains the query, goal plan, and output type needed to re-run an agent
//

import Foundation

// =============================================================================
// MARK: - Agent Definition
// =============================================================================

/// Persisted definition of an agent that can be re-executed by the scheduler
struct AgentDefinition: Identifiable, Codable {
    let id: UUID
    let query: String
    let outputComponentType: String
    let folderId: UUID?
    let goalPlanJSON: Data
    let createdAt: Date
    
    init(
        id: UUID = UUID(),
        query: String,
        outputComponentType: String,
        folderId: UUID?,
        goalPlanJSON: Data,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.query = query
        self.outputComponentType = outputComponentType
        self.folderId = folderId
        self.goalPlanJSON = goalPlanJSON
        self.createdAt = createdAt
    }
}

// =============================================================================
// MARK: - Agent Definition Store
// =============================================================================

/// Persists agent definitions to disk for re-execution by the widget scheduler
@Observable
@MainActor
final class AgentDefinitionStore {
    
    var definitions: [AgentDefinition] = []
    
    private let storageURL: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bowserDir = appSupport.appendingPathComponent("Bowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: bowserDir, withIntermediateDirectories: true)
        self.storageURL = bowserDir.appendingPathComponent("agent_definitions.json")
        load()
    }
    
    func save(_ definition: AgentDefinition) {
        if let index = definitions.firstIndex(where: { $0.id == definition.id }) {
            definitions[index] = definition
        } else {
            definitions.append(definition)
        }
        persist()
    }
    
    func delete(_ id: UUID) {
        definitions.removeAll { $0.id == id }
        persist()
    }
    
    func get(_ id: UUID) -> AgentDefinition? {
        definitions.first { $0.id == id }
    }
    
    // MARK: - Persistence
    
    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            definitions = try JSONDecoder().decode([AgentDefinition].self, from: data)
        } catch {
            print("[AgentDefinitionStore] Failed to load: \(error)")
        }
    }
    
    private func persist() {
        do {
            let data = try JSONEncoder().encode(definitions)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[AgentDefinitionStore] Failed to save: \(error)")
        }
    }
}
