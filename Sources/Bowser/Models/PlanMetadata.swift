//
//  PlanMetadata.swift
//  Bowser
//
//  Lightweight plan metadata for list display and multi-plan management
//

import Foundation

// =============================================================================
// MARK: - Plan Metadata
// =============================================================================

/// Lightweight plan summary for list display
/// Used in plan list view and command palette search
struct PlanMetadata: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let intent: String
    let createdAt: Date
    var updatedAt: Date
    var nodeCount: Int
    var completedNodeCount: Int
    
    init(
        id: UUID = UUID(),
        name: String,
        intent: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        nodeCount: Int = 0,
        completedNodeCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.intent = intent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.nodeCount = nodeCount
        self.completedNodeCount = completedNodeCount
    }
    
    /// Progress percentage (0.0 to 1.0)
    var progress: Double {
        guard nodeCount > 0 else { return 0.0 }
        return Double(completedNodeCount) / Double(nodeCount)
    }
    
    /// Formatted progress string (e.g., "12/20 tasks")
    var progressText: String {
        "\(completedNodeCount)/\(nodeCount) tasks"
    }
    
    /// Relative time string (e.g., "2d ago", "1w ago")
    var relativeTimeText: String {
        let now = Date()
        let interval = now.timeIntervalSince(updatedAt)
        
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)
        let weeks = Int(interval / 604800)
        
        if minutes < 60 {
            return minutes <= 1 ? "Just now" : "\(minutes)m ago"
        } else if hours < 24 {
            return "\(hours)h ago"
        } else if days < 7 {
            return "\(days)d ago"
        } else if weeks < 4 {
            return "\(weeks)w ago"
        } else {
            let months = Int(interval / 2592000)
            return months < 12 ? "\(months)mo ago" : "1y+ ago"
        }
    }
}

// =============================================================================
// MARK: - Plan Document
// =============================================================================

/// Complete plan state for persistence
/// Combines metadata with full plan state for file storage
struct PlanDocument: Codable {
    var metadata: PlanMetadata
    let savedState: PlanState.SavedPlanState
    let clarificationQuestions: [ClarificationQuestion]
    let clarificationAnswers: [String: [String]]  // UUID string keys for JSON compatibility
    
    init(
        metadata: PlanMetadata,
        savedState: PlanState.SavedPlanState,
        clarificationQuestions: [ClarificationQuestion],
        clarificationAnswers: [UUID: [String]]
    ) {
        self.metadata = metadata
        self.savedState = savedState
        self.clarificationQuestions = clarificationQuestions
        // Convert UUID keys to strings for JSON serialization
        self.clarificationAnswers = Dictionary(
            uniqueKeysWithValues: clarificationAnswers.map { (key, value) in
                (key.uuidString, value)
            }
        )
    }
    
    /// Get clarification answers with UUID keys
    func getClarificationAnswers() -> [UUID: [String]] {
        Dictionary(
            uniqueKeysWithValues: clarificationAnswers.compactMap { (key, value) in
                guard let uuid = UUID(uuidString: key) else { return nil }
                return (uuid, value)
            }
        )
    }
    
    /// Update metadata node counts from plan tree
    mutating func updateNodeCounts() {
        guard let root = savedState.planRoot else {
            metadata.nodeCount = 0
            metadata.completedNodeCount = 0
            return
        }
        
        var totalNodes = 0
        var completedNodes = 0
        
        func countNodes(_ node: PlanNode) {
            totalNodes += 1
            if node.isCompleted {
                completedNodes += 1
            }
            for child in node.children {
                countNodes(child)
            }
        }
        
        countNodes(root)
        
        metadata.nodeCount = totalNodes
        metadata.completedNodeCount = completedNodes
        metadata.updatedAt = Date()
    }
}
