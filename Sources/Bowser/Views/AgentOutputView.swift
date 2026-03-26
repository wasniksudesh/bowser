//
//  AgentOutputView.swift
//  Bowser
//
//  Renders consolidated agent output using UILibrary components
//  Reused in both agent mode completion and homescreen widgets
//

import SwiftUI

// =============================================================================
// MARK: - Agent Output View
// =============================================================================

/// Renders a consolidated output (componentType + componentData) using the UILibrary
struct AgentOutputView: View {
    
    let componentType: String
    let componentData: Any?
    let summary: String
    var compact: Bool = false
    @Bindable var browserState: BrowserState
    
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 16) {
            if !summary.isEmpty && !compact {
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            
            componentView
        }
    }
    
    // MARK: - Component Router
    
    @ViewBuilder
    private var componentView: some View {
        let normalizedType = componentType.lowercased().replacingOccurrences(of: "_", with: "")
        
        switch normalizedType {
        case "carousel":
            renderCarousel()
        case "spotlist":
            renderSpotList()
        case "destinationcard":
            renderDestinationCard()
        case "highlightstab", "highlightstabs":
            renderHighlightsTab()
        case "table":
            renderTable()
        case "chart":
            renderChart()
        case "textblock":
            renderTextBlock()
        case "list":
            renderList()
        default:
            fallbackView
        }
    }
    
    // MARK: - Component Renderers
    
    @ViewBuilder
    private func renderCarousel() -> some View {
        if let dataArray = componentData as? [[String: Any]] {
            let cards = dataArray.compactMap { dict -> CarouselCardData? in
                // Rich product card shape: {title, image?, url?, description?}
                if let title = dict["title"] as? String {
                    return CarouselCardData(
                        title: title,
                        description: dict["description"] as? String,
                        image: dict["image"] as? String,
                        url: dict["url"] as? String,
                        caption: dict["caption"] as? String
                    )
                }
                // Legacy image-only shape: {url, caption?}
                if let url = dict["url"] as? String {
                    return CarouselCardData(legacyURL: url, caption: dict["caption"] as? String)
                }
                return nil
            }
            CarouselComponent(images: cards, isLoading: false)
        } else {
            CarouselComponent(images: [], isLoading: false)
        }
    }
    
    @ViewBuilder
    private func renderSpotList() -> some View {
        let dataArray: [[String: Any]]? =
            (componentData as? [String: Any]).flatMap { $0["spots"] as? [[String: Any]] }
            ?? (componentData as? [[String: Any]])
        
        if let dataArray = dataArray {
            let spots = dataArray.compactMap { dict -> SpotData? in
                guard let name = dict["name"] as? String,
                      let description = dict["description"] as? String else { return nil }
                return SpotData(name: name, description: description, url: dict["url"] as? String)
            }
            SpotListComponent(spots: spots, isLoading: false, title: "", browserState: browserState)
        } else {
            SpotListComponent(isLoading: false, title: "", browserState: browserState)
        }
    }
    
    @ViewBuilder
    private func renderDestinationCard() -> some View {
        if let dict = componentData as? [String: Any],
           let title = dict["title"] as? String,
           let subtitle = dict["subtitle"] as? String,
           let badge = dict["badge"] as? String,
           let badgeLabel = dict["badgeLabel"] as? String {
            DestinationCardComponent(
                data: DestinationCardData(title: title, subtitle: subtitle, badge: badge, badgeLabel: badgeLabel),
                isLoading: false
            )
        } else {
            DestinationCardComponent(data: nil, isLoading: false)
        }
    }
    
    @ViewBuilder
    private func renderHighlightsTab() -> some View {
        if let dict = componentData as? [String: Any],
           let tabsArray = dict["tabs"] as? [[String: Any]] {
            let tabs = tabsArray.compactMap { tabDict -> HighlightTab? in
                guard let id = tabDict["id"] as? String,
                      let title = tabDict["title"] as? String,
                      let description = tabDict["description"] as? String else { return nil }
                let spots: [SpotData] = (tabDict["spots"] as? [[String: Any]])?.compactMap { spotDict in
                    guard let name = spotDict["name"] as? String,
                          let desc = spotDict["description"] as? String else { return nil }
                    return SpotData(name: name, description: desc, url: spotDict["url"] as? String)
                } ?? []
                return HighlightTab(id: id, title: title, description: description, spots: spots)
            }
            HighlightsTabComponent(data: HighlightsData(sectionTitle: nil, tabs: tabs), isLoading: false)
        } else {
            HighlightsTabComponent(data: nil, isLoading: false)
        }
    }
    
    @ViewBuilder
    private func renderTable() -> some View {
        if let dict = componentData as? [String: Any],
           let columnsArray = dict["columns"] as? [[String: Any]],
           let rowsArray = dict["rows"] as? [[String]] {
            let columns = columnsArray.compactMap { col -> TableColumn? in
                guard let key = col["key"] as? String, let label = col["label"] as? String else { return nil }
                return TableColumn(key: key, label: label)
            }
            TableComponent(data: TableData(columns: columns, rows: rowsArray), isLoading: false)
        } else {
            TableComponent(data: nil, isLoading: false)
        }
    }
    
    @ViewBuilder
    private func renderChart() -> some View {
        if let dict = componentData as? [String: Any],
           let chartTypeStr = dict["chartType"] as? String ?? dict["chart_type"] as? String,
           let chartType = ChartType(rawValue: chartTypeStr),
           let labels = dict["labels"] as? [String],
           let datasetsArray = dict["datasets"] as? [[String: Any]] {
            let datasets = datasetsArray.compactMap { ds -> ChartDataset? in
                guard let label = ds["label"] as? String,
                      let values = ds["values"] as? [Double] else { return nil }
                return ChartDataset(label: label, values: values)
            }
            ChartComponent(data: ChartData(chartType: chartType, labels: labels, datasets: datasets), isLoading: false)
        } else {
            ChartComponent(data: nil, isLoading: false)
        }
    }
    
    @ViewBuilder
    private func renderTextBlock() -> some View {
        if let dict = componentData as? [String: Any],
           let content = dict["content"] as? String {
            let format = TextFormat(rawValue: dict["format"] as? String ?? "plain") ?? .plain
            TextBlockComponent(data: TextBlockData(content: content, format: format), isLoading: false)
        } else {
            TextBlockComponent(data: nil, isLoading: false)
        }
    }
    
    @ViewBuilder
    private func renderList() -> some View {
        if let dict = componentData as? [String: Any],
           let itemsArray = dict["items"] as? [[String: Any]] {
            let items = itemsArray.map { item in
                ListItem(label: item["label"] as? String ?? "", value: item["value"] as? String)
            }
            ListComponent(data: ListData(items: items), isLoading: false)
        } else {
            ListComponent(data: nil, isLoading: false)
        }
    }
    
    private var fallbackView: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("Unknown component: \(componentType)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
        )
    }
}
