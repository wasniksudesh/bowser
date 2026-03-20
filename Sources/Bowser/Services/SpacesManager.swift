// SpacesManager.swift - Arc-Style Spaces/Workspaces Management
// Observable manager for Arc-style spaces with persistence handler pattern

import Foundation
import SwiftUI

// =============================================================================
// MARK: - Spaces Manager (Observable)
// =============================================================================

/// Dedicated manager for Arc-style spaces/workspaces
/// Handles navigation, CRUD operations, and persistence via handler pattern
/// Independently testable and free from direct UserDefaults coupling
@Observable
@MainActor
final class SpacesManager {
    
    // MARK: - Properties
    
    /// All available spaces
    private(set) var spaces: [Space] = []
    
    /// Index of the currently active space
    private(set) var currentIndex: Int = 0
    
    /// Handler called when spaces change (for persistence)
    var spacesPersistenceHandler: ((Data) -> Void)?
    
    /// Handler called when current index changes (for persistence)
    var indexPersistenceHandler: ((Int) -> Void)?
    
    /// Handler called to load spaces data
    var spacesLoadHandler: (() -> Data?)?
    
    /// Handler called to load current index
    var indexLoadHandler: (() -> Int?)?
    
    // MARK: - Computed Properties
    
    /// Currently active space
    var currentSpace: Space {
        get {
            guard spaces.indices.contains(currentIndex) else {
                return spaces.first ?? Space.defaultSpace
            }
            return spaces[currentIndex]
        }
        set {
            if let index = spaces.firstIndex(where: { $0.id == newValue.id }) {
                currentIndex = index
                persistIndex()
            }
        }
    }
    
    /// Total number of spaces
    var count: Int {
        spaces.count
    }
    
    /// Whether there are multiple spaces
    var hasMultipleSpaces: Bool {
        spaces.count > 1
    }
    
    // MARK: - Initialization
    
    init(
        defaults: [Space]? = nil,
        spacesPersistenceHandler: ((Data) -> Void)? = nil,
        indexPersistenceHandler: ((Int) -> Void)? = nil,
        spacesLoadHandler: (() -> Data?)? = nil,
        indexLoadHandler: (() -> Int?)? = nil
    ) {
        self.spacesPersistenceHandler = spacesPersistenceHandler
        self.indexPersistenceHandler = indexPersistenceHandler
        self.spacesLoadHandler = spacesLoadHandler
        self.indexLoadHandler = indexLoadHandler
        
        // Load spaces from handler or use defaults
        if let loadHandler = spacesLoadHandler, let data = loadHandler() {
            do {
                let decoded = try JSONDecoder().decode([Space].self, from: data)
                self.spaces = decoded.isEmpty ? (defaults ?? Space.defaults) : decoded
            } catch {
                self.spaces = defaults ?? Space.defaults
            }
        } else {
            self.spaces = defaults ?? Space.defaults
        }
        
        // Load current index
        if let indexHandler = indexLoadHandler, let savedIndex = indexHandler() {
            self.currentIndex = spaces.indices.contains(savedIndex) ? savedIndex : 0
        }
    }
    
    // MARK: - Navigation
    
    /// Switch to a specific space
    func switchTo(_ space: Space) {
        guard let index = spaces.firstIndex(where: { $0.id == space.id }) else {
            return
        }
        switchTo(index: index)
    }
    
    /// Switch to a space by index
    func switchTo(index: Int) {
        guard spaces.indices.contains(index) else {
            return
        }
        currentIndex = index
        persistIndex()
    }
    
    /// Navigate to the next space (wraps around)
    func next() {
        let nextIndex = (currentIndex + 1) % spaces.count
        switchTo(index: nextIndex)
    }
    
    /// Navigate to the previous space (wraps around)
    func previous() {
        let previousIndex = currentIndex > 0 ? currentIndex - 1 : spaces.count - 1
        switchTo(index: previousIndex)
    }
    
    // MARK: - Space Management
    
    /// Create a new space and optionally switch to it
    @discardableResult
    func create(name: String? = nil, color: Color? = nil, switchTo shouldSwitch: Bool = true) -> Space {
        let spaceName = name ?? "Space \(spaces.count + 1)"
        let spaceColor = color ?? Self.randomSpaceColor
        
        let newSpace = Space(name: spaceName, color: spaceColor)
        spaces.append(newSpace)
        persistSpaces()
        
        if shouldSwitch {
            currentIndex = spaces.count - 1
            persistIndex()
        }
        
        return newSpace
    }
    
    /// Delete a space (keeps at least one space)
    func delete(_ space: Space) {
        guard spaces.count > 1 else {
            return
        }
        
        guard let index = spaces.firstIndex(where: { $0.id == space.id }) else {
            return
        }
        
        spaces.remove(at: index)
        
        // Adjust current index if necessary
        if currentIndex >= spaces.count {
            currentIndex = spaces.count - 1
        } else if currentIndex > index {
            currentIndex -= 1
        }
        
        persistSpaces()
        persistIndex()
    }
    
    /// Delete a space by ID
    func delete(id: UUID) {
        guard let space = spaces.first(where: { $0.id == id }) else { return }
        delete(space)
    }
    
    /// Rename a space
    func rename(_ space: Space, to newName: String) {
        guard let index = spaces.firstIndex(where: { $0.id == space.id }) else {
            return
        }
        spaces[index].name = newName
        persistSpaces()
    }
    
    /// Change a space's color
    func setColor(_ space: Space, to color: Color) {
        guard let index = spaces.firstIndex(where: { $0.id == space.id }) else {
            return
        }
        spaces[index].color = color
        persistSpaces()
    }
    
    // MARK: - Tab Management within Spaces
    
    /// Add a tab ID to a space
    func addTab(_ tabId: UUID, to space: Space) {
        guard let index = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        if !spaces[index].tabIds.contains(tabId) {
            spaces[index].tabIds.append(tabId)
            persistSpaces()
        }
    }
    
    /// Add a tab ID to the current space
    func addTabToCurrent(_ tabId: UUID) {
        addTab(tabId, to: currentSpace)
    }
    
    /// Remove a tab ID from a space
    func removeTab(_ tabId: UUID, from space: Space) {
        guard let index = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        spaces[index].tabIds.removeAll { $0 == tabId }
        persistSpaces()
    }
    
    /// Remove a tab ID from all spaces
    func removeTabFromAll(_ tabId: UUID) {
        for index in spaces.indices {
            spaces[index].tabIds.removeAll { $0 == tabId }
        }
        persistSpaces()
    }
    
    /// Move a tab from one space to another
    func moveTab(_ tabId: UUID, from sourceSpace: Space, to targetSpace: Space) {
        removeTab(tabId, from: sourceSpace)
        addTab(tabId, to: targetSpace)
    }
    
    /// Get tabs for a specific space
    func tabs(for space: Space) -> [UUID] {
        guard let index = spaces.firstIndex(where: { $0.id == space.id }) else { return [] }
        return spaces[index].tabIds
    }
    
    // MARK: - Bulk Operations
    
    /// Replace all spaces (useful for sync/import)
    func setSpaces(_ newSpaces: [Space]) {
        spaces = newSpaces.isEmpty ? Space.defaults : newSpaces
        if currentIndex >= spaces.count {
            currentIndex = 0
        }
        persistSpaces()
        persistIndex()
    }
    
    /// Reset to default spaces
    func resetToDefaults() {
        spaces = Space.defaults
        currentIndex = 0
        persistSpaces()
        persistIndex()
    }
    
    // MARK: - Persistence
    
    private func persistSpaces() {
        guard let handler = spacesPersistenceHandler else { return }
        do {
            let data = try JSONEncoder().encode(spaces)
            handler(data)
        } catch {
            // Silently fail - logging handled at app level
        }
    }
    
    private func persistIndex() {
        indexPersistenceHandler?(currentIndex)
    }
    
    /// Load spaces from external data
    func load(spacesData: Data?, indexValue: Int?) {
        if let data = spacesData {
            do {
                let decoded = try JSONDecoder().decode([Space].self, from: data)
                spaces = decoded.isEmpty ? Space.defaults : decoded
            } catch {
                // Keep existing on decode failure
            }
        }
        
        if let index = indexValue, spaces.indices.contains(index) {
            currentIndex = index
        }
    }
    
    /// Export spaces as encoded data
    func export() -> (spaces: Data?, index: Int) {
        (try? JSONEncoder().encode(spaces), currentIndex)
    }
    
    // MARK: - Helpers
    
    /// Random color for new spaces
    private static var randomSpaceColor: Color {
        Space.availableColors.randomElement() ?? .blue
    }
}
