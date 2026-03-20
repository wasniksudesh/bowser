//
//  UIComponentRegistry.swift
//  Bowser
//
//  Registry of available UI components with metadata for LLM planning
//

import SwiftUI

// =============================================================================
// MARK: - Component Type
// =============================================================================

/// Types of UI components available in the library
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

/// Metadata about a UI component for LLM planning
struct UIComponentMetadata: Codable {
    let type: UIComponentType
    let displayName: String
    let description: String
    let compatibleDataTypes: [String]
    let expectedDataSchema: String
    let sizeHint: String // "small", "medium", "large", "auto"
}

// =============================================================================
// MARK: - UI Component Registry
// =============================================================================

/// Central registry of all available UI components
/// Used by the LLM to plan layouts
struct UIComponentRegistry {
    
    /// All available components
    static let components: [UIComponentMetadata] = [
        UIComponentMetadata(
            type: .carousel,
            displayName: "Image Carousel",
            description: "Horizontal scrollable carousel of images with optional captions. Perfect for showcasing photos, destinations, or visual content.",
            compatibleDataTypes: ["images", "photos", "gallery"],
            expectedDataSchema: """
            [{
                "url": "https://example.com/image.jpg",
                "caption": "Optional caption text"
            }]
            """,
            sizeHint: "large"
        ),
        
        UIComponentMetadata(
            type: .destinationCard,
            displayName: "Destination Card",
            description: "Compact card showing a destination with title, subtitle, badge, and ideal stay duration. Perfect for travel planning.",
            compatibleDataTypes: ["destination", "location", "place"],
            expectedDataSchema: """
            {
                "title": "Matera",
                "subtitle": "Italy · Cave city",
                "badge": "2-3 days",
                "badgeLabel": "Ideal stay"
            }
            """,
            sizeHint: "small"
        ),
        
        UIComponentMetadata(
            type: .spotList,
            displayName: "Spot List",
            description: "Vertical list of spots/locations with names and descriptions. Shows circular indicators and supports multiple items.",
            compatibleDataTypes: ["list", "spots", "locations", "places"],
            expectedDataSchema: """
            [{
                "name": "Sassi di Matera",
                "description": "UNESCO-listed cave districts"
            }]
            """,
            sizeHint: "medium"
        ),
        
        UIComponentMetadata(
            type: .highlightsTab,
            displayName: "Highlights Tab View",
            description: "Tabbed interface showing highlights for different destinations. Includes description text and list of top spots. Perfect for comparing multiple destinations or categories.",
            compatibleDataTypes: ["tabs", "highlights", "categories", "comparisons"],
            expectedDataSchema: """
            {
                "tabs": [{
                    "id": "unique_id",
                    "title": "Tab Name",
                    "description": "Overview description of this category/destination",
                    "spots": [{
                        "id": "spot_id",
                        "name": "Spot Name",
                        "description": "Brief description"
                    }]
                }]
            }
            Return 2-4 tabs for comparison.
            """,
            sizeHint: "large"
        ),
        
        UIComponentMetadata(
            type: .map,
            displayName: "Interactive Map",
            description: "Interactive Google Maps panel for location-based queries. Shows map for destinations, places, or location searches. Collapsible and resizable.",
            compatibleDataTypes: ["map", "location", "destination", "place", "geography"],
            expectedDataSchema: """
            {
                "targetURL": "https://www.google.com/maps/search/?api=1&query=Starbucks+near+Times+Square",
                "title": "Map View",
                "searchQuery": "Starbucks near Times Square"
            }
            """,
            sizeHint: "large"
        ),
        
        UIComponentMetadata(
            type: .table,
            displayName: "Data Table",
            description: "Sortable table for structured data with columns and rows. Perfect for displaying lists of items, commits, API responses, or any tabular data.",
            compatibleDataTypes: ["table", "list", "data", "rows", "records"],
            expectedDataSchema: """
            {
                "columns": [
                    {"key": "id", "label": "ID"},
                    {"key": "name", "label": "Name"}
                ],
                "rows": [
                    ["1", "Item 1"],
                    ["2", "Item 2"]
                ]
            }
            """,
            sizeHint: "medium"
        ),
        
        UIComponentMetadata(
            type: .chart,
            displayName: "Chart",
            description: "Data visualization with support for bar, line, and pie charts. Shows trends, comparisons, and distributions.",
            compatibleDataTypes: ["chart", "graph", "visualization", "metrics", "statistics"],
            expectedDataSchema: """
            {
                "chart_type": "bar",
                "labels": ["Jan", "Feb", "Mar"],
                "datasets": [
                    {"label": "Sales", "values": [100, 150, 200]}
                ]
            }
            """,
            sizeHint: "medium"
        ),
        
        UIComponentMetadata(
            type: .textBlock,
            displayName: "Text Block",
            description: "Rich text display with support for plain text, markdown, and code blocks. Includes copy functionality.",
            compatibleDataTypes: ["text", "content", "summary", "description", "code"],
            expectedDataSchema: """
            {
                "content": "Text content here",
                "format": "plain"
            }
            Format can be: plain, markdown, or code
            """,
            sizeHint: "auto"
        ),
        
        UIComponentMetadata(
            type: .list,
            displayName: "List",
            description: "Simple bullet list or key-value pairs. Perfect for displaying properties, attributes, or enumerated items.",
            compatibleDataTypes: ["list", "items", "properties", "attributes"],
            expectedDataSchema: """
            {
                "items": [
                    {"label": "Key", "value": "Value"},
                    {"label": "Item without value"}
                ]
            }
            """,
            sizeHint: "small"
        )
    ]
    
    /// Get metadata for a specific component type
    static func metadata(for type: UIComponentType) -> UIComponentMetadata? {
        components.first { $0.type == type }
    }
    
    /// Get all component metadata as JSON for LLM prompt
    static func allMetadataJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        guard let data = try? encoder.encode(components),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        
        return json
    }
}
