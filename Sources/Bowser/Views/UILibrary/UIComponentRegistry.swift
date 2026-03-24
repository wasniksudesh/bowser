//
//  UIComponentRegistry.swift
//  Bowser
//
//  Registry of available UI components.
//  Mirrors Sources/Bowser/Views/UILibrary/Schemas/registry.json exactly.
//
//  When adding a new component:
//    1. Create its Swift view in UILibrary/
//    2. Add a case to UIComponentType
//    3. Add an entry to UIComponentRegistry.components (copy values from registry.json)
//    4. Add a renderer entry in ComponentRendererRegistry.swift
//    5. Add/update the schema JSON files
//

import SwiftUI

// =============================================================================
// MARK: - Component Type
// =============================================================================

enum UIComponentType: String, Codable, CaseIterable {
    case carousel
    case destinationCard
    case spotList
    case highlightsTab
    case map
    case table
    case chart
    case textBlock
    case list
}

// =============================================================================
// MARK: - Component Metadata
// =============================================================================

struct UIComponentMetadata {
    let type: UIComponentType
    let displayName: String
    let description: String
    let category: String
    let compatibleDataTypes: [String]
    let sizeHint: String
    /// Default data source for this component type ("llm" or "api").
    let dataSource: String
    /// Data sources this component type can support (may include both "llm" and "api").
    let supportedDataSources: [String]

    init(
        type: UIComponentType,
        displayName: String,
        description: String,
        category: String,
        compatibleDataTypes: [String],
        sizeHint: String,
        dataSource: String = "llm",
        supportedDataSources: [String]? = nil
    ) {
        self.type = type
        self.displayName = displayName
        self.description = description
        self.category = category
        self.compatibleDataTypes = compatibleDataTypes
        self.sizeHint = sizeHint
        self.dataSource = dataSource
        self.supportedDataSources = supportedDataSources ?? [dataSource]
    }
}

// =============================================================================
// MARK: - UI Component Registry
// =============================================================================

/// Central registry of all available UI components.
/// Values here must mirror Schemas/registry.json — the Python backend is the
/// authoritative prompt-generation source; this registry is used by the Swift
/// stream client to send the component catalogue to the server.
struct UIComponentRegistry {

    static let components: [UIComponentMetadata] = [
        UIComponentMetadata(
            type: .carousel,
            displayName: "Image Carousel",
            description: "Horizontal scrolling image gallery with captions. Perfect for showcasing photos, destinations, or visual content.",
            category: "media",
            compatibleDataTypes: ["images", "photos", "gallery"],
            sizeHint: "large",
            dataSource: "llm"
        ),
        UIComponentMetadata(
            type: .destinationCard,
            displayName: "Destination Card",
            description: "Compact card showing a destination with title, subtitle, badge, and ideal stay duration. Perfect for travel planning.",
            category: "content",
            compatibleDataTypes: ["destination", "location", "place"],
            sizeHint: "small",
            dataSource: "llm"
        ),
        UIComponentMetadata(
            type: .spotList,
            displayName: "Spot List",
            description: "Vertical list of spots/locations with names and descriptions. Shows clickable items with URLs.",
            category: "content",
            compatibleDataTypes: ["list", "spots", "locations", "places"],
            sizeHint: "medium",
            dataSource: "llm"
        ),
        UIComponentMetadata(
            type: .highlightsTab,
            displayName: "Highlights Tab View",
            description: "Tabbed interface for comparing multiple categories or destinations. Each tab contains a description and list of spots.",
            category: "navigation",
            compatibleDataTypes: ["tabs", "highlights", "categories", "comparisons"],
            sizeHint: "large",
            dataSource: "llm"
        ),
        UIComponentMetadata(
            type: .map,
            displayName: "Interactive Map",
            description: "Interactive Google Maps panel for location-based queries. Collapsible and resizable.",
            category: "media",
            compatibleDataTypes: ["map", "location", "destination", "place", "geography"],
            sizeHint: "large",
            dataSource: "llm"
        ),
        UIComponentMetadata(
            type: .table,
            displayName: "Data Table",
            description: "Sortable table for structured data with columns and rows. Works with LLM-generated data or a live API/database source.",
            category: "data",
            compatibleDataTypes: ["table", "list", "data", "rows", "records", "metrics"],
            sizeHint: "medium",
            dataSource: "llm",
            supportedDataSources: ["llm", "api"]
        ),
        UIComponentMetadata(
            type: .chart,
            displayName: "Chart",
            description: "Data visualization with support for bar, line, and pie charts. Works with LLM-generated data or a live API/database source.",
            category: "data",
            compatibleDataTypes: ["chart", "graph", "visualization", "metrics", "statistics"],
            sizeHint: "medium",
            dataSource: "llm",
            supportedDataSources: ["llm", "api"]
        ),
        UIComponentMetadata(
            type: .textBlock,
            displayName: "Text Block",
            description: "Rich text display with support for plain text, markdown, and code blocks. Includes copy functionality.",
            category: "content",
            compatibleDataTypes: ["text", "content", "summary", "description", "code"],
            sizeHint: "auto",
            dataSource: "llm"
        ),
        UIComponentMetadata(
            type: .list,
            displayName: "List",
            description: "Key-value pairs or bullet list. Perfect for displaying properties, attributes, or enumerated items.",
            category: "content",
            compatibleDataTypes: ["list", "items", "properties", "attributes"],
            sizeHint: "small",
            dataSource: "llm"
        ),
    ]

    static func metadata(for type: UIComponentType) -> UIComponentMetadata? {
        components.first { $0.type == type }
    }
}
