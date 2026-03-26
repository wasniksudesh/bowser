//
//  TableComponent.swift
//  Bowser
//
//  Reusable table component for structured data
//  Part of UILibrary for agent output rendering
//

import SwiftUI

// =============================================================================
// MARK: - Table Data Models
// =============================================================================

struct TableColumn: Identifiable {
    let id: UUID
    let key: String
    let label: String
    
    init(id: UUID = UUID(), key: String, label: String) {
        self.id = id
        self.key = key
        self.label = label
    }
}

struct TableData {
    let columns: [TableColumn]
    let rows: [[String]]
}

// =============================================================================
// MARK: - Table Component
// =============================================================================

struct TableComponent: View {
    
    let data: TableData?
    let isLoading: Bool
    var maxColumnWidth: CGFloat = 280
    
    @State private var sortColumn: String? = nil
    @State private var sortAscending: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                loadingState
            } else if let data = data, !data.columns.isEmpty {
                tableContent(data: data)
            } else {
                emptyState
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }
    
    // MARK: - Table Content
    
    private func tableContent(data: TableData) -> some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Header
                GridRow {
                    ForEach(data.columns) { column in
                        headerCell(column: column)
                    }
                }
                
                Divider()
                    .gridCellUnsizedAxes(.horizontal)
                
                // Rows
                ForEach(Array(sortedRows(data: data).enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                            dataCell(text: cell, isAlt: index % 2 != 0)
                        }
                    }
                    
                    if index < data.rows.count - 1 {
                        Divider()
                            .gridCellUnsizedAxes(.horizontal)
                    }
                }
            }
        }
    }
    
    // MARK: - Cells
    
    private func headerCell(column: TableColumn) -> some View {
        Button(action: {
            if sortColumn == column.key {
                sortAscending.toggle()
            } else {
                sortColumn = column.key
                sortAscending = true
            }
        }) {
            HStack(spacing: 4) {
                Text(column.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(nil)
                
                if sortColumn == column.key {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minWidth: 100, maxWidth: maxColumnWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .controlColor).opacity(0.2))
    }
    
    private func dataCell(text: String, isAlt: Bool) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .lineLimit(nil)
            .frame(minWidth: 100, maxWidth: maxColumnWidth, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isAlt ? Color(nsColor: .controlColor).opacity(0.05) : Color.clear)
    }
    
    // MARK: - Sorted Rows
    
    private func sortedRows(data: TableData) -> [[String]] {
        guard let sortColumn = sortColumn,
              let columnIndex = data.columns.firstIndex(where: { $0.key == sortColumn }) else {
            return data.rows
        }
        
        return data.rows.sorted { row1, row2 in
            guard columnIndex < row1.count && columnIndex < row2.count else {
                return false
            }
            
            let val1 = row1[columnIndex]
            let val2 = row2[columnIndex]
            
            if let num1 = Double(val1), let num2 = Double(val2) {
                return sortAscending ? num1 < num2 : num1 > num2
            }
            
            return sortAscending ? val1 < val2 : val1 > val2
        }
    }
    
    // MARK: - Loading State
    
    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            
            Text("Loading table...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tablecells")
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
struct TableComponent_Previews: PreviewProvider {
    static var previews: some View {
        let data = TableData(
            columns: [
                TableColumn(key: "by", label: "By"),
                TableColumn(key: "hn_id", label: "Hn_Id"),
                TableColumn(key: "score", label: "Score"),
                TableColumn(key: "time", label: "Time"),
                TableColumn(key: "title", label: "Title")
            ],
            rows: [
                ["andrew_zhong", "47526486", "50", "2026-03-26T03:55:52+00:00", "Show HN: Robust LLM Extractor"],
                ["RicDan", "47528914", "3", "2026-03-26T10:54:28+00:00", "Show HN: Alexandria, free open-source news aggregation and classification suite"],
                ["virtuallytd", "47528178", "2", "2026-03-26T09:08:41+00:00", "Show HN: Hooky – AI powered webhooks"]
            ]
        )
        
        return VStack(spacing: 20) {
            TableComponent(data: data, isLoading: false)
            TableComponent(data: nil, isLoading: true)
        }
        .padding(20)
        .frame(width: 800)
    }
}
#endif
