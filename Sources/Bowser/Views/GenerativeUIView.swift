//
//  GenerativeUIView.swift
//  Bowser
//
//  Main view for displaying AI-generated UI layouts
//  Shows dynamic components based on leaf node context
//

import SwiftUI

// =============================================================================
// MARK: - Generative UI View
// =============================================================================

/// Main view that displays AI-generated UI layouts with dynamic components
struct GenerativeUIView: View {
    
    @Bindable var planState: PlanState
    @Bindable var browserState: BrowserState
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content area - will show dynamic components
            ScrollView {
                VStack(spacing: 20) {
                    if let node = planState.selectedLeafNode {
                        if let error = planState.errorMessage {
                            // Error state
                            errorStateView(error: error)
                        } else if planState.isLoading && planState.generativeUILayout == nil {
                            // Initial loading state
                            loadingStateView
                        } else if let layout = planState.generativeUILayout {
                            // Render components based on layout
                            dynamicComponentsView(layout: layout)
                        } else {
                            // Placeholder content
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Generative UI Active")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                
                                Text("Selected Leaf: \(node.title)")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                
                                if let description = node.description {
                                    Text(description)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                        )
                                }
                                
                                // Demo components with mock data
                                placeholderComponentsGrid
                            }
                            .padding(24)
                        }
                    } else {
                        Text("No leaf node selected")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(40)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .task(id: planState.selectedLeafNode?.id) {
            // Fetch layout when leaf node changes
            if planState.selectedLeafNode != nil {
                // Clear previous layout and data when switching leaves
                if planState.generativeUILayout != nil {
                    planState.generativeUILayout = nil
                    planState.componentDataCache = [:]
                    planState.loadingComponentIds = []
                }
                await planState.fetchLayoutPlan()
            }
        }
    }
    
    // MARK: - Loading State View
    
    private var loadingStateView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Designing layout...")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("AI is analyzing your task and creating the perfect layout")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    // MARK: - Error State View
    
    private func errorStateView(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            Text("Layout Generation Failed")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                Task {
                    planState.errorMessage = nil
                    await planState.fetchLayoutPlan()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    // MARK: - Dynamic Components View
    
    private func dynamicComponentsView(layout: GenerativeUILayout) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Render each component based on layout
            ForEach(Array(layout.components.enumerated()), id: \.element.id) { index, component in
                componentView(for: component)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
                    .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.1), value: layout.components.count)
            }
        }
        .padding(24)
    }
    
    @ViewBuilder
    private func componentView(for spec: UIComponentSpec) -> some View {
        let isLoading = planState.loadingComponentIds.contains(spec.id)
        let data = planState.componentDataCache[spec.id]
        
        VStack(alignment: .leading, spacing: 8) {
            // Component header
            Text(spec.type.capitalized.replacingOccurrences(of: "_", with: " "))
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            
            // Render specific component - normalize type to handle both snake_case and camelCase
            let normalizedType = spec.type.lowercased().replacingOccurrences(of: "_", with: "")
            
            switch normalizedType {
            case "carousel":
                renderCarousel(data: data, isLoading: isLoading)
            case "destinationcard":
                renderDestinationCard(data: data, isLoading: isLoading)
            case "spotlist":
                renderSpotList(data: data, isLoading: isLoading)
            case "highlightstab", "highlightstabs":
                renderHighlightsTab(data: data, isLoading: isLoading)
            case "map":
                renderMap(data: data, isLoading: isLoading)
            case "table":
                renderTable(data: data, isLoading: isLoading)
            case "chart":
                renderChart(data: data, isLoading: isLoading)
            case "textblock":
                renderTextBlock(data: data, isLoading: isLoading)
            case "list":
                renderList(data: data, isLoading: isLoading)
            default:
                Text("Unknown component type: \(spec.type)")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.1))
                    )
            }
        }
    }
    
    // MARK: - Component Renderers
    
    @ViewBuilder
    private func renderCarousel(data: Any?, isLoading: Bool) -> some View {
        if let dataArray = data as? [[String: Any]] {
            let images = dataArray.compactMap { dict -> CarouselImageData? in
                guard let url = dict["url"] as? String else { return nil }
                let caption = dict["caption"] as? String
                return CarouselImageData(url: url, caption: caption)
            }
            CarouselComponent(images: images, isLoading: false)
        } else {
            CarouselComponent(images: [], isLoading: isLoading)
        }
    }
    
    @ViewBuilder
    private func renderDestinationCard(data: Any?, isLoading: Bool) -> some View {
        if let dict = data as? [String: Any],
           let title = dict["title"] as? String,
           let subtitle = dict["subtitle"] as? String,
           let badge = dict["badge"] as? String,
           let badgeLabel = dict["badgeLabel"] as? String {
            DestinationCardComponent(
                data: DestinationCardData(
                    title: title,
                    subtitle: subtitle,
                    badge: badge,
                    badgeLabel: badgeLabel
                ),
                isLoading: false
            )
        } else {
            DestinationCardComponent(data: nil, isLoading: isLoading)
        }
    }
    
    @ViewBuilder
    private func renderSpotList(data: Any?, isLoading: Bool) -> some View {
        // API returns { "spots": [ { "name", "description", "url"? }, ... ] }; also support raw array
        let dataArray: [[String: Any]]? = (data as? [String: Any]).flatMap { $0["spots"] as? [[String: Any]] }
            ?? (data as? [[String: Any]])
        if let dataArray = dataArray {
            let spots = dataArray.compactMap { dict -> SpotData? in
                guard let name = dict["name"] as? String,
                      let description = dict["description"] as? String else { return nil }
                let url = dict["url"] as? String
                return SpotData(name: name, description: description, url: url)
            }
            SpotListComponent(spots: spots, isLoading: false, title: "Top Spots", browserState: browserState)
        } else {
            SpotListComponent(isLoading: isLoading, title: "Top Spots", browserState: browserState)
        }
    }
    
    @ViewBuilder
    private func renderHighlightsTab(data: Any?, isLoading: Bool) -> some View {
        if let dict = data as? [String: Any],
           let tabsArray = dict["tabs"] as? [[String: Any]] {
            let sectionTitle = dict["sectionTitle"] as? String
            let tabs = tabsArray.compactMap { tabDict -> HighlightTab? in
                // Full format: id, title, description, spots: [{ name, description, url? }]
                if let id = tabDict["id"] as? String,
                   let title = tabDict["title"] as? String,
                   let description = tabDict["description"] as? String {
                    let spots: [SpotData]
                    if let spotsArray = tabDict["spots"] as? [[String: Any]] {
                        spots = spotsArray.compactMap { spotDict -> SpotData? in
                            guard let name = spotDict["name"] as? String,
                                  let desc = spotDict["description"] as? String else { return nil }
                            let url = spotDict["url"] as? String
                            return SpotData(name: name, description: desc, url: url)
                        }
                    } else {
                        spots = []
                    }
                    return HighlightTab(id: id, title: title, description: description, spots: spots)
                }
                // API format: platform, description, url (no nested spots)
                if let platform = tabDict["platform"] as? String,
                   let description = tabDict["description"] as? String {
                    let title = tabDict["title"] as? String ?? platform
                    let id = tabDict["id"] as? String ?? platform
                    let url = tabDict["url"] as? String
                    let spot = SpotData(name: platform, description: description, url: url)
                    return HighlightTab(id: id, title: title, description: description, spots: [spot])
                }
                return nil
            }
            
            HighlightsTabComponent(data: HighlightsData(sectionTitle: sectionTitle, tabs: tabs), isLoading: false)
        } else {
            HighlightsTabComponent(data: nil, isLoading: isLoading)
        }
    }
    
    @ViewBuilder
    private func renderMap(data: Any?, isLoading: Bool) -> some View {
        if let dict = data as? [String: Any],
           let targetURL = dict["targetURL"] as? String {
            let title = dict["title"] as? String
            let searchQuery = dict["searchQuery"] as? String
            MapsComponent(
                data: MapsData(targetURL: targetURL, title: title, searchQuery: searchQuery),
                isLoading: false
            )
        } else {
            MapsComponent(data: nil, isLoading: isLoading)
        }
    }
    
    @ViewBuilder
    private func renderTable(data: Any?, isLoading: Bool) -> some View {
        if let dict = data as? [String: Any],
           let columnsArray = dict["columns"] as? [[String: Any]],
           let rowsArray = dict["rows"] as? [[String]] {
            let columns = columnsArray.compactMap { col -> TableColumn? in
                guard let key = col["key"] as? String, let label = col["label"] as? String else { return nil }
                return TableColumn(key: key, label: label)
            }
            TableComponent(data: TableData(columns: columns, rows: rowsArray), isLoading: false)
        } else {
            TableComponent(data: nil, isLoading: isLoading)
        }
    }
    
    @ViewBuilder
    private func renderChart(data: Any?, isLoading: Bool) -> some View {
        if let dict = data as? [String: Any],
           let chartTypeStr = dict["chart_type"] as? String,
           let chartType = ChartType(rawValue: chartTypeStr),
           let labels = dict["labels"] as? [String],
           let datasetsArray = dict["datasets"] as? [[String: Any]] {
            let datasets = datasetsArray.compactMap { ds -> ChartDataset? in
                guard let label = ds["label"] as? String else { return nil }
                if let values = ds["values"] as? [Double] {
                    return ChartDataset(label: label, values: values)
                }
                if let rawValues = ds["values"] as? [Any] {
                    let values = rawValues.compactMap { ($0 as? NSNumber)?.doubleValue }
                    guard !values.isEmpty else { return nil }
                    return ChartDataset(label: label, values: values)
                }
                return nil
            }
            ChartComponent(data: ChartData(chartType: chartType, labels: labels, datasets: datasets), isLoading: false)
        } else {
            ChartComponent(data: nil, isLoading: isLoading)
        }
    }
    
    @ViewBuilder
    private func renderTextBlock(data: Any?, isLoading: Bool) -> some View {
        if let dict = data as? [String: Any],
           let content = dict["content"] as? String {
            let formatStr = dict["format"] as? String ?? "plain"
            let format = TextFormat(rawValue: formatStr) ?? .plain
            TextBlockComponent(data: TextBlockData(content: content, format: format), isLoading: false)
        } else {
            TextBlockComponent(data: nil, isLoading: isLoading)
        }
    }
    
    @ViewBuilder
    private func renderList(data: Any?, isLoading: Bool) -> some View {
        if let dict = data as? [String: Any],
           let itemsArray = dict["items"] as? [[String: Any]] {
            let items = itemsArray.map { item in
                ListItem(
                    label: item["label"] as? String ?? "",
                    value: item["value"] as? String
                )
            }
            ListComponent(data: ListData(items: items), isLoading: false)
        } else {
            ListComponent(data: nil, isLoading: isLoading)
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16))
                .foregroundStyle(.blue)
            
            Text("AI-Generated Layout")
                .font(.headline)
                .foregroundStyle(.primary)
            
            Spacer()
            
            // Refresh button
            if planState.generativeUILayout != nil {
                Button(action: {
                    Task {
                        planState.generativeUILayout = nil
                        planState.componentDataCache = [:]
                        planState.loadingComponentIds = []
                        await planState.fetchLayoutPlan()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Regenerate layout")
            }
            
            // Status indicator
            if planState.isLoading {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Loading")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Components Grid with Mock Data
    
    private var placeholderComponentsGrid: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("UI Components Demo (Mock Data)")
                .font(.headline)
                .foregroundStyle(.primary)
            
            // Destination Cards Row
            VStack(alignment: .leading, spacing: 12) {
                Text("Destination Cards")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    DestinationCardComponent(
                        data: DestinationCardData(
                            title: "Matera",
                            subtitle: "Italy · Cave city",
                            badge: "2-3 days",
                            badgeLabel: "Ideal stay"
                        ),
                        isLoading: false
                    )
                    
                    DestinationCardComponent(
                        data: DestinationCardData(
                            title: "Mostar",
                            subtitle: "Bosnia & Herzegovina · Ottoman city",
                            badge: "2 days",
                            badgeLabel: "Ideal stay"
                        ),
                        isLoading: false
                    )
                }
            }
            
            // Spot List
            VStack(alignment: .leading, spacing: 12) {
                Text("Spot List")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                
                SpotListComponent(
                    spots: [
                        SpotData(
                            name: "Sassi di Matera",
                            description: "UNESCO-listed cave districts"
                        ),
                        SpotData(
                            name: "Casa Grotta",
                            description: "Restored cave home museum"
                        ),
                        SpotData(
                            name: "Chiesa di Santa Maria de Idris",
                            description: "Rock church with frescoes"
                        )
                    ],
                    isLoading: false,
                    title: "Top Spots",
                    browserState: browserState
                )
            }
            
            // Carousel with mock images
            VStack(alignment: .leading, spacing: 12) {
                Text("Image Carousel")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                
                CarouselComponent(
                    images: [
                        CarouselImageData(
                            url: "https://picsum.photos/400/300?random=1",
                            caption: "Beautiful sunset in Matera"
                        ),
                        CarouselImageData(
                            url: "https://picsum.photos/400/300?random=2",
                            caption: "Ancient cave dwellings"
                        ),
                        CarouselImageData(
                            url: "https://picsum.photos/400/300?random=3",
                            caption: "Historic architecture"
                        )
                    ],
                    isLoading: false
                )
            }
        }
    }
    
    private func placeholderCard(title: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.blue.opacity(0.5))
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.1), lineWidth: 4)
                        )
                )
        )
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct GenerativeUIView_Previews: PreviewProvider {
    static var previews: some View {
        let planState = PlanState()
        let browserState = BrowserState()
        GenerativeUIView(planState: planState, browserState: browserState)
            .frame(width: 800, height: 600)
    }
}
#endif
