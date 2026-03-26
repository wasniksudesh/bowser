//
//  AgentStepOutputView.swift
//  Bowser
//
//  Renders operation agent output artifacts
//  Uses UILibrary components based on displayType
//

import SwiftUI

// =============================================================================
// MARK: - Agent Step Output View
// =============================================================================

/// Renders output artifacts from operation agents
/// Selects appropriate UILibrary component based on displayType
struct AgentStepOutputView: View {
    
    let artifact: OutputArtifact
    @Bindable var browserState: BrowserState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: displayTypeIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
                
                Text(artifact.type.capitalized)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(formatTimestamp(artifact.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Content based on display type
            outputContent
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }
    
    // MARK: - Output Content
    
    @ViewBuilder
    private var outputContent: some View {
        switch artifact.artifactData {
        case .text(let data):
            renderText(data: data)
            
        case .table(let data):
            renderTable(data: data)
            
        case .list(let data):
            renderList(data: data)
            
        case .chart(let data):
            renderChart(data: data)

        case .carousel(let data):
            renderCarousel(data: data)
        }
    }
    
    // MARK: - Renderers
    
    @ViewBuilder
    private func renderText(data: TextArtifactData) -> some View {
        let textData = TextBlockData(
            content: data.content,
            format: TextFormat(rawValue: data.format) ?? .plain
        )
        TextBlockComponent(data: textData, isLoading: false)
    }
    
    @ViewBuilder
    private func renderTable(data: TableArtifactData) -> some View {
        let tableColumns = data.columns.map { col in
            TableColumn(key: col.key, label: col.label)
        }
        let tableData = TableData(columns: tableColumns, rows: data.rows)
        TableComponent(data: tableData, isLoading: false)
    }
    
    @ViewBuilder
    private func renderList(data: ListArtifactData) -> some View {
        let listItems = data.items.map { item in
            ListItem(label: item.label, value: item.value)
        }
        let listData = ListData(items: listItems)
        ListComponent(data: listData, isLoading: false)
    }
    
    @ViewBuilder
    private func renderChart(data: ChartArtifactData) -> some View {
        let chartDatasets = data.datasets.map { ds in
            ChartDataset(label: ds.label, values: ds.values)
        }
        let chartData = ChartData(
            chartType: ChartType(rawValue: data.chartType) ?? .bar,
            labels: data.labels,
            datasets: chartDatasets
        )
        ChartComponent(data: chartData, isLoading: false)
    }

    @ViewBuilder
    private func renderCarousel(data: CarouselArtifactData) -> some View {
        CarouselComponent(images: data.cards, isLoading: false)
    }
    
    // MARK: - Helpers
    
    private var displayTypeIcon: String {
        switch artifact.artifactData {
        case .table:
            return "tablecells"
        case .chart:
            return "chart.bar"
        case .text:
            return "doc.text"
        case .list:
            return "list.bullet"
        case .carousel:
            return "rectangle.stack"
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct AgentStepOutputView_Previews: PreviewProvider {
    static var previews: some View {
        let browserState = BrowserState()
        
        // Table artifact
        let tableData = TableArtifactData(
            columns: [
                TableColumnData(key: "sha", label: "SHA"),
                TableColumnData(key: "message", label: "Message"),
                TableColumnData(key: "author", label: "Author")
            ],
            rows: [
                ["abc123", "Initial commit", "John Doe"],
                ["def456", "Add feature", "Jane Smith"],
                ["ghi789", "Fix bug", "Bob Johnson"]
            ]
        )
        let tableArtifact = OutputArtifact(
            artifactId: "artifact-1",
            type: "table",
            artifactData: .table(tableData)
        )
        
        // Text artifact
        let textData = TextArtifactData(
            content: "This is a summary of the commits. The repository has seen 3 commits in the last week.",
            format: "plain"
        )
        let textArtifact = OutputArtifact(
            artifactId: "artifact-2",
            type: "text",
            artifactData: .text(textData)
        )
        
        return VStack(spacing: 20) {
            AgentStepOutputView(artifact: tableArtifact, browserState: browserState)
            AgentStepOutputView(artifact: textArtifact, browserState: browserState)
        }
        .padding(20)
        .frame(width: 700)
    }
}
#endif
