// HomescreenSearchResultsView.swift
// Glassmorphism popup that renders AI search results using GenerativeUI components

import SwiftUI

// =============================================================================
// MARK: - Search Results Popup
// =============================================================================

struct HomescreenSearchResultsView: View {

    @Bindable var searchState: HomescreenSearchState
    @Bindable var browserState: BrowserState

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.4)
            contentArea
        }
        .frame(maxWidth: 780, maxHeight: 480)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 20, y: -4)
        .onKeyPress(.escape) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { searchState.dismiss() }
            return .handled
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)

            Text("Results for \"\(searchState.query)\"")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            if searchState.isSearching {
                ProgressView()
                    .controlSize(.mini)
            }

            Button {
                withAnimation(.easeOut(duration: 0.25)) { searchState.dismiss() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        if let error = searchState.errorMessage {
            errorView(error: error)
        } else if searchState.isSearching && searchState.generativeUILayout == nil {
            loadingView
        } else if let layout = searchState.generativeUILayout {
            componentsScrollView(layout: layout)
        } else {
            emptyView
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Searching...")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Error

    private func errorView(error: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text("Something went wrong")
                .font(.system(size: 14, weight: .semibold))

            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                searchState.submitSearch(query: searchState.query)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No results yet")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Components Scroll

    private func componentsScrollView(layout: GenerativeUILayout) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(Array(layout.components.enumerated()), id: \.element.id) { index, spec in
                    componentView(for: spec)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        ))
                        .animation(
                            .easeOut(duration: 0.3).delay(Double(index) * 0.08),
                            value: layout.components.count
                        )
                }
            }
            .padding(20)
        }
    }

    // MARK: - Component Router (all 9 types)

    @ViewBuilder
    private func componentView(for spec: UIComponentSpec) -> some View {
        let isLoading = searchState.loadingComponentIds.contains(spec.id)
        let data = searchState.componentDataCache[spec.id]
        let normalizedType = spec.type.lowercased().replacingOccurrences(of: "_", with: "")

        VStack(alignment: .leading, spacing: 6) {
            Text(spec.type.capitalized.replacingOccurrences(of: "_", with: " "))
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

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
                Text("Unknown component: \(spec.type)")
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
            }
        }
    }

    // MARK: - Existing 5 Renderers

    @ViewBuilder
    private func renderCarousel(data: Any?, isLoading: Bool) -> some View {
        if let dataArray = data as? [[String: Any]] {
            let images = dataArray.compactMap { dict -> CarouselImageData? in
                guard let url = dict["url"] as? String else { return nil }
                return CarouselImageData(url: url, caption: dict["caption"] as? String)
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
                data: DestinationCardData(title: title, subtitle: subtitle, badge: badge, badgeLabel: badgeLabel),
                isLoading: false
            )
        } else {
            DestinationCardComponent(data: nil, isLoading: isLoading)
        }
    }

    @ViewBuilder
    private func renderSpotList(data: Any?, isLoading: Bool) -> some View {
        let dataArray: [[String: Any]]? =
            (data as? [String: Any]).flatMap { $0["spots"] as? [[String: Any]] }
            ?? (data as? [[String: Any]])
        if let dataArray {
            let spots = dataArray.compactMap { dict -> SpotData? in
                guard let name = dict["name"] as? String,
                      let description = dict["description"] as? String else { return nil }
                return SpotData(name: name, description: description, url: dict["url"] as? String)
            }
            SpotListComponent(spots: spots, isLoading: false, title: "Top Results", browserState: browserState)
        } else {
            SpotListComponent(isLoading: isLoading, title: "Top Results", browserState: browserState)
        }
    }

    @ViewBuilder
    private func renderHighlightsTab(data: Any?, isLoading: Bool) -> some View {
        if let dict = data as? [String: Any],
           let tabsArray = dict["tabs"] as? [[String: Any]] {
            let sectionTitle = dict["sectionTitle"] as? String
            let tabs = tabsArray.compactMap { tabDict -> HighlightTab? in
                if let id = tabDict["id"] as? String,
                   let title = tabDict["title"] as? String,
                   let description = tabDict["description"] as? String {
                    let spots: [SpotData] = (tabDict["spots"] as? [[String: Any]])?.compactMap { spotDict in
                        guard let name = spotDict["name"] as? String,
                              let desc = spotDict["description"] as? String else { return nil }
                        return SpotData(name: name, description: desc, url: spotDict["url"] as? String)
                    } ?? []
                    return HighlightTab(id: id, title: title, description: description, spots: spots)
                }
                if let platform = tabDict["platform"] as? String,
                   let description = tabDict["description"] as? String {
                    let title = tabDict["title"] as? String ?? platform
                    let id = tabDict["id"] as? String ?? platform
                    let spot = SpotData(name: platform, description: description, url: tabDict["url"] as? String)
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
            MapsComponent(
                data: MapsData(targetURL: targetURL, title: dict["title"] as? String, searchQuery: dict["searchQuery"] as? String),
                isLoading: false
            )
        } else {
            MapsComponent(data: nil, isLoading: isLoading)
        }
    }

    // MARK: - New 4 Renderers

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
                guard let label = ds["label"] as? String,
                      let values = ds["values"] as? [Double] else {
                    // Try parsing from Int/NSNumber arrays
                    guard let label = ds["label"] as? String,
                          let rawValues = ds["values"] as? [Any] else { return nil }
                    let values = rawValues.compactMap { ($0 as? NSNumber)?.doubleValue }
                    guard !values.isEmpty else { return nil }
                    return ChartDataset(label: label, values: values)
                }
                return ChartDataset(label: label, values: values)
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
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct HomescreenSearchResultsView_Previews: PreviewProvider {
    static var previews: some View {
        let state = HomescreenSearchState()
        state.query = "Best restaurants in Tokyo"
        state.showResults = true

        return HomescreenSearchResultsView(
            searchState: state,
            browserState: BrowserState()
        )
        .frame(width: 900, height: 700)
    }
}
#endif
