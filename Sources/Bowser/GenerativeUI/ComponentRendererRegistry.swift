//
//  ComponentRendererRegistry.swift
//  Bowser
//
//  Registry-driven component renderer.
//  Maps component type strings to SwiftUI views without a switch statement.
//
//  To add a new component:
//    1. Create its Swift view in UILibrary/
//    2. Add one entry to the `renderers` dictionary below
//    That's it — no other file needs to change.
//

import SwiftUI

// =============================================================================
// MARK: - Component Renderer Registry
// =============================================================================

@MainActor
struct ComponentRendererRegistry {

    // MARK: - Public API

    /// Returns the SwiftUI view for a given component spec.
    /// Falls back to an "unsupported component" placeholder for unknown types.
    @ViewBuilder
    static func view(
        for spec: UIComponentSpec,
        data: Any?,
        isLoading: Bool,
        browserState: BrowserState
    ) -> some View {
        if let renderer = renderers[spec.type] {
            renderer(data, isLoading, browserState)
        } else {
            unsupportedComponentView(type: spec.type)
        }
    }

    // MARK: - Renderer Dictionary
    //
    // Each value is a closure: (data: Any?, isLoading: Bool, browserState: BrowserState) -> AnyView
    // Type-specific data parsing lives entirely inside each closure.

    private static let renderers: [String: (Any?, Bool, BrowserState) -> AnyView] = [

        "carousel": { data, isLoading, _ in
            AnyView(carouselView(data: data, isLoading: isLoading))
        },

        "destinationCard": { data, isLoading, _ in
            AnyView(destinationCardView(data: data, isLoading: isLoading))
        },

        "spotList": { data, isLoading, browserState in
            AnyView(spotListView(data: data, isLoading: isLoading, browserState: browserState))
        },

        "highlightsTab": { data, isLoading, _ in
            AnyView(highlightsTabView(data: data, isLoading: isLoading))
        },

        "highlightsTabs": { data, isLoading, _ in       // alias for plural variant
            AnyView(highlightsTabView(data: data, isLoading: isLoading))
        },

        "map": { data, isLoading, _ in
            AnyView(mapView(data: data, isLoading: isLoading))
        },

        "table": { data, isLoading, _ in
            AnyView(tableView(data: data, isLoading: isLoading))
        },

        "chart": { data, isLoading, _ in
            AnyView(chartView(data: data, isLoading: isLoading))
        },

        "textBlock": { data, isLoading, _ in
            AnyView(textBlockView(data: data, isLoading: isLoading))
        },

        "list": { data, isLoading, _ in
            AnyView(listView(data: data, isLoading: isLoading))
        },
    ]

    // MARK: - Per-Component Data Parsers

    private static func carouselView(data: Any?, isLoading: Bool) -> some View {
        let images: [CarouselImageData]
        if let array = data as? [[String: Any]] {
            images = array.compactMap { dict in
                guard let url = dict["url"] as? String else { return nil }
                return CarouselImageData(url: url, caption: dict["caption"] as? String)
            }
        } else {
            images = []
        }
        return CarouselComponent(images: images, isLoading: isLoading && images.isEmpty)
    }

    private static func destinationCardView(data: Any?, isLoading: Bool) -> some View {
        let cardData: DestinationCardData?
        if let dict = data as? [String: Any],
           let title = dict["title"] as? String,
           let subtitle = dict["subtitle"] as? String,
           let badge = dict["badge"] as? String,
           let badgeLabel = dict["badgeLabel"] as? String {
            cardData = DestinationCardData(title: title, subtitle: subtitle, badge: badge, badgeLabel: badgeLabel)
        } else {
            cardData = nil
        }
        return DestinationCardComponent(data: cardData, isLoading: isLoading && cardData == nil)
    }

    private static func spotListView(data: Any?, isLoading: Bool, browserState: BrowserState) -> some View {
        let spots: [SpotData]
        if let dict = data as? [String: Any], let spotsArray = dict["spots"] as? [[String: Any]] {
            spots = spotsArray.compactMap { parseSpot($0) }
        } else if let array = data as? [[String: Any]] {
            spots = array.compactMap { parseSpot($0) }
        } else {
            spots = []
        }
        return SpotListComponent(
            spots: spots,
            isLoading: isLoading && spots.isEmpty,
            title: "Top Spots",
            browserState: browserState
        )
    }

    private static func highlightsTabView(data: Any?, isLoading: Bool) -> some View {
        let highlightsData: HighlightsData?
        if let dict = data as? [String: Any], let tabsArray = dict["tabs"] as? [[String: Any]] {
            let sectionTitle = dict["sectionTitle"] as? String
            let tabs = tabsArray.compactMap { parseHighlightTab($0) }
            highlightsData = tabs.isEmpty ? nil : HighlightsData(sectionTitle: sectionTitle, tabs: tabs)
        } else {
            highlightsData = nil
        }
        return HighlightsTabComponent(data: highlightsData, isLoading: isLoading && highlightsData == nil)
    }

    private static func mapView(data: Any?, isLoading: Bool) -> some View {
        let mapsData: MapsData?
        if let dict = data as? [String: Any], let targetURL = dict["targetURL"] as? String {
            mapsData = MapsData(
                targetURL: targetURL,
                title: dict["title"] as? String,
                searchQuery: dict["searchQuery"] as? String
            )
        } else {
            mapsData = nil
        }
        return MapsComponent(data: mapsData, isLoading: isLoading && mapsData == nil)
    }

    private static func tableView(data: Any?, isLoading: Bool) -> some View {
        let tableData: TableData?
        if let dict = data as? [String: Any],
           let columnsArray = dict["columns"] as? [[String: Any]],
           let rowsArray = dict["rows"] as? [[String]] {
            let columns = columnsArray.compactMap { col -> TableColumn? in
                guard let key = col["id"] as? String, let title = col["title"] as? String else { return nil }
                return TableColumn(key: key, label: title)
            }
            tableData = TableData(columns: columns, rows: rowsArray)
        } else {
            tableData = nil
        }
        return TableComponent(data: tableData, isLoading: isLoading && tableData == nil)
    }

    private static func chartView(data: Any?, isLoading: Bool) -> some View {
        let chartData: ChartData?
        if let dict = data as? [String: Any],
           let chartTypeStr = dict["chartType"] as? String,
           let chartType = ChartType(rawValue: chartTypeStr),
           let datasetsArray = dict["datasets"] as? [[String: Any]] {
            let labels = dict["labels"] as? [String] ?? []
            let datasets = datasetsArray.compactMap { ds -> ChartDataset? in
                guard let label = ds["label"] as? String,
                      let values = ds["data"] as? [Double] else { return nil }
                return ChartDataset(label: label, values: values)
            }
            chartData = ChartData(chartType: chartType, labels: labels, datasets: datasets)
        } else {
            chartData = nil
        }
        return ChartComponent(data: chartData, isLoading: isLoading && chartData == nil)
    }

    private static func textBlockView(data: Any?, isLoading: Bool) -> some View {
        let textData: TextBlockData?
        if let dict = data as? [String: Any],
           let content = dict["content"] as? String,
           let formatStr = dict["format"] as? String,
           let format = TextFormat(rawValue: formatStr) {
            textData = TextBlockData(content: content, format: format)
        } else {
            textData = nil
        }
        return TextBlockComponent(data: textData, isLoading: isLoading && textData == nil)
    }

    private static func listView(data: Any?, isLoading: Bool) -> some View {
        let listData: ListData?
        if let dict = data as? [String: Any], let itemsArray = dict["items"] as? [[String: Any]] {
            let items = itemsArray.compactMap { item -> ListItem? in
                guard let label = item["label"] as? String else { return nil }
                return ListItem(label: label, value: item["value"] as? String)
            }
            listData = items.isEmpty ? nil : ListData(items: items)
        } else {
            listData = nil
        }
        return ListComponent(data: listData, isLoading: isLoading && listData == nil)
    }

    // MARK: - Shared Parsing Helpers

    private static func parseSpot(_ dict: [String: Any]) -> SpotData? {
        guard let name = dict["name"] as? String,
              let description = dict["description"] as? String else { return nil }
        return SpotData(name: name, description: description, url: dict["url"] as? String)
    }

    private static func parseHighlightTab(_ dict: [String: Any]) -> HighlightTab? {
        // Standard format: id, title, description, spots
        if let id = dict["id"] as? String,
           let title = dict["title"] as? String,
           let description = dict["description"] as? String {
            let spots: [SpotData]
            if let spotsArray = dict["spots"] as? [[String: Any]] {
                spots = spotsArray.compactMap { parseSpot($0) }
            } else {
                spots = []
            }
            return HighlightTab(id: id, title: title, description: description, spots: spots)
        }
        // Compact platform format: platform, description, url
        if let platform = dict["platform"] as? String,
           let description = dict["description"] as? String {
            let title = dict["title"] as? String ?? platform
            let id = dict["id"] as? String ?? platform
            let spot = SpotData(name: platform, description: description, url: dict["url"] as? String)
            return HighlightTab(id: id, title: title, description: description, spots: [spot])
        }
        return nil
    }

    // MARK: - Fallback View

    private static func unsupportedComponentView(type: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.square.dashed")
                .foregroundStyle(.secondary)
            Text("Unsupported component: \(type)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        )
    }
}
