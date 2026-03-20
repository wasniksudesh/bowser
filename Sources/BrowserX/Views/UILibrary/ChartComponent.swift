//
//  ChartComponent.swift
//  Bowser
//
//  Chart visualization component using Swift Charts
//  Part of UILibrary for agent output rendering
//

import SwiftUI
import Charts

// =============================================================================
// MARK: - Chart Data Models
// =============================================================================

enum ChartType: String, Codable {
    case bar
    case line
    case pie
}

struct ChartDataset: Identifiable {
    let id: UUID
    let label: String
    let values: [Double]
    
    init(id: UUID = UUID(), label: String, values: [Double]) {
        self.id = id
        self.label = label
        self.values = values
    }
}

struct ChartData {
    let chartType: ChartType
    let labels: [String]
    let datasets: [ChartDataset]
}

// =============================================================================
// MARK: - Chart Component
// =============================================================================

/// Chart visualization component with support for bar, line, and pie charts
struct ChartComponent: View {
    
    let data: ChartData?
    let isLoading: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                loadingState
            } else if let data = data {
                chartContent(data: data)
            } else {
                emptyState
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }
    
    // MARK: - Chart Content
    
    private func chartContent(data: ChartData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Chart
            Group {
                switch data.chartType {
                case .bar:
                    barChart(data: data)
                case .line:
                    lineChart(data: data)
                case .pie:
                    pieChart(data: data)
                }
            }
            .frame(height: 250)
            .padding(16)
            
            // Legend
            if data.datasets.count > 1 {
                legend(datasets: data.datasets)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }
    
    // MARK: - Bar Chart
    
    private func barChart(data: ChartData) -> some View {
        Chart {
            ForEach(Array(data.datasets.enumerated()), id: \.element.id) { datasetIndex, dataset in
                ForEach(Array(dataset.values.enumerated()), id: \.offset) { index, value in
                    if index < data.labels.count {
                        BarMark(
                            x: .value("Category", data.labels[index]),
                            y: .value("Value", value)
                        )
                        .foregroundStyle(by: .value("Dataset", dataset.label))
                    }
                }
            }
        }
        .chartLegend(.hidden)
    }
    
    // MARK: - Line Chart
    
    private func lineChart(data: ChartData) -> some View {
        Chart {
            ForEach(Array(data.datasets.enumerated()), id: \.element.id) { datasetIndex, dataset in
                ForEach(Array(dataset.values.enumerated()), id: \.offset) { index, value in
                    if index < data.labels.count {
                        LineMark(
                            x: .value("Category", data.labels[index]),
                            y: .value("Value", value)
                        )
                        .foregroundStyle(by: .value("Dataset", dataset.label))
                        .symbol(by: .value("Dataset", dataset.label))
                    }
                }
            }
        }
        .chartLegend(.hidden)
    }
    
    // MARK: - Pie Chart
    
    private func pieChart(data: ChartData) -> some View {
        // For pie chart, use first dataset only
        let dataset = data.datasets.first
        
        return Chart {
            if let dataset = dataset {
                ForEach(Array(dataset.values.enumerated()), id: \.offset) { index, value in
                    if index < data.labels.count {
                        SectorMark(
                            angle: .value("Value", value),
                            innerRadius: .ratio(0.5),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("Category", data.labels[index]))
                    }
                }
            }
        }
        .chartLegend(.hidden)
    }
    
    // MARK: - Legend
    
    private func legend(datasets: [ChartDataset]) -> some View {
        HStack(spacing: 16) {
            ForEach(datasets) { dataset in
                HStack(spacing: 6) {
                    Circle()
                        .fill(colorForDataset(dataset))
                        .frame(width: 8, height: 8)
                    
                    Text(dataset.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func colorForDataset(_ dataset: ChartDataset) -> Color {
        // Simple color assignment based on dataset index
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red]
        let hash = abs(dataset.label.hashValue)
        return colors[hash % colors.count]
    }
    
    // MARK: - Loading State
    
    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            
            Text("Loading chart...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("No data")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct ChartComponent_Previews: PreviewProvider {
    static var previews: some View {
        let barData = ChartData(
            chartType: .bar,
            labels: ["Jan", "Feb", "Mar", "Apr", "May"],
            datasets: [
                ChartDataset(label: "Sales", values: [120, 150, 180, 140, 200]),
                ChartDataset(label: "Expenses", values: [80, 90, 100, 95, 110])
            ]
        )
        
        let lineData = ChartData(
            chartType: .line,
            labels: ["Week 1", "Week 2", "Week 3", "Week 4"],
            datasets: [
                ChartDataset(label: "Users", values: [100, 150, 180, 220])
            ]
        )
        
        let pieData = ChartData(
            chartType: .pie,
            labels: ["Chrome", "Safari", "Firefox", "Edge"],
            datasets: [
                ChartDataset(label: "Browser Share", values: [45, 30, 15, 10])
            ]
        )
        
        return VStack(spacing: 20) {
            Text("Bar Chart")
                .font(.headline)
            ChartComponent(data: barData, isLoading: false)
            
            Text("Line Chart")
                .font(.headline)
            ChartComponent(data: lineData, isLoading: false)
            
            Text("Pie Chart")
                .font(.headline)
            ChartComponent(data: pieData, isLoading: false)
        }
        .padding(20)
        .frame(width: 600)
    }
}
#endif
