//
//  WidgetState.swift
//  Bowser
//
//  Homescreen widget state management
//  Tracks widget instances, their positions, and cached display data
//

import Foundation
import SwiftUI

// =============================================================================
// MARK: - Widget Instance
// =============================================================================

/// A widget instance displayed on the homescreen
struct HomescreenWidgetInstance: Identifiable, Codable {
    let id: UUID
    let widgetId: String
    let agentDefinitionId: UUID
    let folderId: UUID?
    let query: String
    let outputComponentType: String
    var position: CGPoint
    var size: CGSize
    var isVisible: Bool
    
    init(
        id: UUID = UUID(),
        widgetId: String,
        agentDefinitionId: UUID,
        folderId: UUID? = nil,
        query: String,
        outputComponentType: String,
        position: CGPoint = CGPoint(x: 200, y: 200),
        size: CGSize = CGSize(width: 320, height: 280),
        isVisible: Bool = true
    ) {
        self.id = id
        self.widgetId = widgetId
        self.agentDefinitionId = agentDefinitionId
        self.folderId = folderId
        self.query = query
        self.outputComponentType = outputComponentType
        self.position = position
        self.size = size
        self.isVisible = isVisible
    }
    
    enum CodingKeys: String, CodingKey {
        case id, widgetId, agentDefinitionId, folderId, query, outputComponentType
        case posX, posY, width, height, isVisible
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        widgetId = try c.decode(String.self, forKey: .widgetId)
        agentDefinitionId = try c.decode(UUID.self, forKey: .agentDefinitionId)
        folderId = try c.decodeIfPresent(UUID.self, forKey: .folderId)
        query = try c.decode(String.self, forKey: .query)
        outputComponentType = try c.decode(String.self, forKey: .outputComponentType)
        let x = try c.decode(CGFloat.self, forKey: .posX)
        let y = try c.decode(CGFloat.self, forKey: .posY)
        position = CGPoint(x: x, y: y)
        let w = try c.decode(CGFloat.self, forKey: .width)
        let h = try c.decode(CGFloat.self, forKey: .height)
        size = CGSize(width: w, height: h)
        isVisible = try c.decode(Bool.self, forKey: .isVisible)
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(widgetId, forKey: .widgetId)
        try c.encode(agentDefinitionId, forKey: .agentDefinitionId)
        try c.encodeIfPresent(folderId, forKey: .folderId)
        try c.encode(query, forKey: .query)
        try c.encode(outputComponentType, forKey: .outputComponentType)
        try c.encode(position.x, forKey: .posX)
        try c.encode(position.y, forKey: .posY)
        try c.encode(size.width, forKey: .width)
        try c.encode(size.height, forKey: .height)
        try c.encode(isVisible, forKey: .isVisible)
    }
}

// =============================================================================
// MARK: - Widget Manager
// =============================================================================

/// Manages homescreen widget instances, caches latest data, tracks unread state
@Observable
@MainActor
final class WidgetManager {
    
    var widgets: [HomescreenWidgetInstance] = []
    var cachedData: [String: Any] = [:]  // widgetId -> latest component_data
    var unreadWidgetIds: Set<String> = []
    
    private let storageURL: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bowserDir = appSupport.appendingPathComponent("Bowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: bowserDir, withIntermediateDirectories: true)
        self.storageURL = bowserDir.appendingPathComponent("homescreen_widgets.json")
        load()
    }
    
    // MARK: - CRUD
    
    func addWidget(_ widget: HomescreenWidgetInstance) {
        widgets.append(widget)
        persist()
    }
    
    func removeWidget(_ id: UUID) {
        if let widget = widgets.first(where: { $0.id == id }) {
            unreadWidgetIds.remove(widget.widgetId)
            cachedData.removeValue(forKey: widget.widgetId)
        }
        widgets.removeAll { $0.id == id }
        persist()
    }
    
    func updatePosition(_ id: UUID, position: CGPoint) {
        if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].position = position
            persist()
        }
    }
    
    func updateSize(_ id: UUID, size: CGSize) {
        if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].size = size
            persist()
        }
    }
    
    func hideWidget(_ id: UUID) {
        if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].isVisible = false
            persist()
        }
    }
    
    func showWidget(_ id: UUID) {
        if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].isVisible = true
            persist()
        }
    }
    
    // MARK: - Data Cache
    
    func updateCachedData(widgetId: String, data: Any) {
        cachedData[widgetId] = data
        unreadWidgetIds.insert(widgetId)
    }
    
    func markRead(widgetId: String) {
        unreadWidgetIds.remove(widgetId)
    }
    
    func hasUnread(forFolder folderId: UUID) -> Bool {
        let folderWidgetIds = Set(
            widgets
                .filter { $0.folderId == folderId }
                .map { $0.widgetId }
        )
        return !unreadWidgetIds.isDisjoint(with: folderWidgetIds)
    }
    
    var visibleWidgets: [HomescreenWidgetInstance] {
        widgets.filter { $0.isVisible }
    }
    
    // MARK: - Persistence
    
    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            widgets = try JSONDecoder().decode([HomescreenWidgetInstance].self, from: data)
        } catch {
            print("[WidgetManager] Failed to load: \(error)")
        }
    }
    
    private func persist() {
        do {
            let data = try JSONEncoder().encode(widgets)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[WidgetManager] Failed to save: \(error)")
        }
    }
    
    // MARK: - Fetch Latest Data from Backend
    
    func refreshWidgetData(widgetId: String) async {
        do {
            let url = URL(string: "http://localhost:8765/api/widgets/\(widgetId)/artifact/latest")!
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let entry = json?["entry"] as? [String: Any],
               let entryData = entry["data"] {
                await MainActor.run {
                    updateCachedData(widgetId: widgetId, data: entryData)
                }
            }
        } catch {
            print("[WidgetManager] Failed to refresh widget \(widgetId): \(error)")
        }
    }
}
