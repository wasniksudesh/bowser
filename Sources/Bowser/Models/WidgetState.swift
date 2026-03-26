//
//  WidgetState.swift
//  Bowser
//
//  Homescreen widget state management
//  Unified system for both agent-driven and self-contained builtin widgets
//

import Foundation
import SwiftUI

// =============================================================================
// MARK: - Widget Kind
// =============================================================================

/// Discriminates between agent-backed widgets and self-contained builtin widgets
enum WidgetKind: String, Codable {
    case agent   // Backed by an agent definition + backend data
    case builtin // Self-contained, no backend dependency
}

// =============================================================================
// MARK: - Widget Instance
// =============================================================================

/// A widget instance displayed on the homescreen.
/// Supports both agent-driven widgets and self-contained builtin widgets.
struct HomescreenWidgetInstance: Identifiable, Codable {
    let id: UUID
    let widgetId: String
    /// The kind of widget. Defaults to `.agent` for backward compatibility.
    let kind: WidgetKind
    /// Agent definition ID. Nil for builtin widgets.
    let agentDefinitionId: UUID?
    let folderId: UUID?
    /// For agent widgets: the original query. For builtin widgets: display label.
    let query: String
    /// For agent widgets: the output component type. For builtin widgets: the builtin type ID.
    let outputComponentType: String
    /// Per-instance configuration for builtin widgets. Empty for agent widgets.
    var configuration: [String: String]
    /// Grid order for the widget grid layout. Lower values appear first.
    var gridOrder: Int
    /// Retained for backward compat with persisted agent widgets; not used for grid layout.
    var position: CGPoint
    var size: CGSize
    var isVisible: Bool

    // MARK: Agent widget init (existing)

    init(
        id: UUID = UUID(),
        widgetId: String,
        agentDefinitionId: UUID,
        folderId: UUID? = nil,
        query: String,
        outputComponentType: String,
        gridOrder: Int = 0,
        position: CGPoint = CGPoint(x: 200, y: 200),
        size: CGSize = CGSize(width: 320, height: 280),
        isVisible: Bool = true
    ) {
        self.id = id
        self.widgetId = widgetId
        self.kind = .agent
        self.agentDefinitionId = agentDefinitionId
        self.folderId = folderId
        self.query = query
        self.outputComponentType = outputComponentType
        self.configuration = [:]
        self.gridOrder = gridOrder
        self.position = position
        self.size = size
        self.isVisible = isVisible
    }

    // MARK: Builtin widget init

    init(
        id: UUID = UUID(),
        builtinTypeId: String,
        displayName: String,
        configuration: [String: String] = [:],
        gridOrder: Int = 0,
        size: CGSize = CGSize(width: 260, height: 280)
    ) {
        self.id = id
        self.widgetId = builtinTypeId + "-" + id.uuidString
        self.kind = .builtin
        self.agentDefinitionId = nil
        self.folderId = nil
        self.query = displayName
        self.outputComponentType = builtinTypeId
        self.configuration = configuration
        self.gridOrder = gridOrder
        self.position = .zero
        self.size = size
        self.isVisible = true
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case id, widgetId, kind, agentDefinitionId, folderId, query, outputComponentType
        case configuration, gridOrder
        case posX, posY, width, height, isVisible
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        widgetId = try c.decode(String.self, forKey: .widgetId)
        kind = (try? c.decode(WidgetKind.self, forKey: .kind)) ?? .agent
        agentDefinitionId = try? c.decodeIfPresent(UUID.self, forKey: .agentDefinitionId)
        folderId = try c.decodeIfPresent(UUID.self, forKey: .folderId)
        query = try c.decode(String.self, forKey: .query)
        outputComponentType = try c.decode(String.self, forKey: .outputComponentType)
        configuration = (try? c.decodeIfPresent([String: String].self, forKey: .configuration)) ?? [:]
        gridOrder = (try? c.decodeIfPresent(Int.self, forKey: .gridOrder)) ?? 0
        let x = (try? c.decode(CGFloat.self, forKey: .posX)) ?? 0
        let y = (try? c.decode(CGFloat.self, forKey: .posY)) ?? 0
        position = CGPoint(x: x, y: y)
        let w = (try? c.decode(CGFloat.self, forKey: .width)) ?? 260
        let h = (try? c.decode(CGFloat.self, forKey: .height)) ?? 280
        size = CGSize(width: w, height: h)
        isVisible = (try? c.decode(Bool.self, forKey: .isVisible)) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(widgetId, forKey: .widgetId)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(agentDefinitionId, forKey: .agentDefinitionId)
        try c.encodeIfPresent(folderId, forKey: .folderId)
        try c.encode(query, forKey: .query)
        try c.encode(outputComponentType, forKey: .outputComponentType)
        try c.encode(configuration, forKey: .configuration)
        try c.encode(gridOrder, forKey: .gridOrder)
        try c.encode(position.x, forKey: .posX)
        try c.encode(position.y, forKey: .posY)
        try c.encode(size.width, forKey: .width)
        try c.encode(size.height, forKey: .height)
        try c.encode(isVisible, forKey: .isVisible)
    }
}

// =============================================================================
// MARK: - Builtin Widget Registry
// =============================================================================

/// Metadata describing a self-contained builtin widget type
struct BuiltinWidgetDescriptor: Identifiable {
    let typeId: String
    let displayName: String
    let icon: String
    let description: String
    let defaultSize: CGSize
    let defaultConfiguration: [String: String]

    var id: String { typeId }
}

/// Catalog of all registered self-contained builtin widget types
final class BuiltinWidgetRegistry: Sendable {

    static let shared = BuiltinWidgetRegistry()

    private let descriptors: [BuiltinWidgetDescriptor] = [
        BuiltinWidgetDescriptor(
            typeId: "timezone-converter",
            displayName: "World Clock",
            icon: "globe",
            description: "Show current times across multiple timezones at a glance.",
            defaultSize: CGSize(width: 280, height: 300),
            defaultConfiguration: ["timezones": "UTC,America/New_York,Europe/London,Asia/Tokyo,Asia/Kolkata"]
        )
    ]

    func allDescriptors() -> [BuiltinWidgetDescriptor] { descriptors }

    func descriptor(for typeId: String) -> BuiltinWidgetDescriptor? {
        descriptors.first { $0.typeId == typeId }
    }
}

// =============================================================================
// MARK: - Widget Manager
// =============================================================================

/// Manages all homescreen widget instances (both agent and builtin),
/// caches latest backend data for agent widgets, tracks unread state.
@Observable
@MainActor
final class WidgetManager {

    var widgets: [HomescreenWidgetInstance] = []
    var cachedData: [String: Any] = [:]  // widgetId -> latest component_data
    var unreadWidgetIds: Set<String> = []

    let builtinRegistry = BuiltinWidgetRegistry.shared

    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bowserDir = appSupport.appendingPathComponent("Bowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: bowserDir, withIntermediateDirectories: true)
        self.storageURL = bowserDir.appendingPathComponent("homescreen_widgets.json")
        load()
    }

    // MARK: - Ordered Access

    /// Visible widgets sorted by gridOrder for grid layout
    var orderedVisibleWidgets: [HomescreenWidgetInstance] {
        widgets.filter { $0.isVisible }.sorted { $0.gridOrder < $1.gridOrder }
    }

    // MARK: - CRUD

    func addWidget(_ widget: HomescreenWidgetInstance) {
        widgets.append(widget)
        persist()
    }

    /// Convenience: create and add a builtin widget from its typeId, appended to end of grid.
    func addBuiltinWidget(typeId: String) {
        guard let descriptor = builtinRegistry.descriptor(for: typeId) else { return }
        let nextOrder = (widgets.map(\.gridOrder).max() ?? -1) + 1
        let placed = HomescreenWidgetInstance(
            builtinTypeId: typeId,
            displayName: descriptor.displayName,
            configuration: descriptor.defaultConfiguration,
            gridOrder: nextOrder,
            size: descriptor.defaultSize
        )
        addWidget(placed)
    }

    func removeWidget(_ id: UUID) {
        if let widget = widgets.first(where: { $0.id == id }) {
            unreadWidgetIds.remove(widget.widgetId)
            cachedData.removeValue(forKey: widget.widgetId)
        }
        widgets.removeAll { $0.id == id }
        reindexGridOrder()
        persist()
    }

    /// Move a widget from one grid position to another, shifting others accordingly
    func moveWidget(fromId: UUID, toIndex: Int) {
        var ordered = orderedVisibleWidgets
        guard let fromIndex = ordered.firstIndex(where: { $0.id == fromId }) else { return }
        guard fromIndex != toIndex else { return }
        let item = ordered.remove(at: fromIndex)
        let safeIndex = max(0, min(toIndex, ordered.count))
        ordered.insert(item, at: safeIndex)
        for (i, widget) in ordered.enumerated() {
            if let idx = widgets.firstIndex(where: { $0.id == widget.id }) {
                widgets[idx].gridOrder = i
            }
        }
        persist()
    }

    /// Re-assigns sequential gridOrder values after removals
    private func reindexGridOrder() {
        let sorted = widgets.sorted { $0.gridOrder < $1.gridOrder }
        for (i, widget) in sorted.enumerated() {
            if let idx = widgets.firstIndex(where: { $0.id == widget.id }) {
                widgets[idx].gridOrder = i
            }
        }
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

    /// Update the configuration dict for a builtin widget
    func updateConfig(_ id: UUID, configuration: [String: String]) {
        if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].configuration = configuration
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

    // MARK: - Fetch Latest Data from Backend (agent widgets only)

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
