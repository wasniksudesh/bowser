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

/// Reusable table component with sortable columns
struct TableComponent: View {
    
    let data: TableData?
    let isLoading: Bool
    
    @State private var sortColumn: String? = nil
    @State private var sortAscending: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                loadingState
            } else if let data = data {
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
            VStack(spacing: 0) {
                // Header row
                headerRow(columns: data.columns)
                
                Divider()
                
                // Data rows
                ForEach(Array(sortedRows(data: data).enumerated()), id: \.offset) { index, row in
                    dataRow(row: row, index: index)
                    
                    if index < data.rows.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .frame(maxHeight: 400)
    }
    
    // MARK: - Header Row
    
    private func headerRow(columns: [TableColumn]) -> some View {
        HStack(spacing: 0) {
            ForEach(columns) { column in
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
                        
                        if sortColumn == column.key {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color(nsColor: .controlColor).opacity(0.2))
                
                if column.id != columns.last?.id {
                    Divider()
                }
            }
        }
    }
    
    // MARK: - Data Row
    
    private func dataRow(row: [String], index: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                Text(cell)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        index % 2 == 0
                            ? Color.clear
                            : Color(nsColor: .controlColor).opacity(0.05)
                    )
                
                if colIndex < row.count - 1 {
                    Divider()
                }
            }
        }
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
            
            // Try numeric comparison first
            if let num1 = Double(val1), let num2 = Double(val2) {
                return sortAscending ? num1 < num2 : num1 > num2
            }
            
            // Fall back to string comparison
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
                TableColumn(key: "sha", label: "SHA"),
                TableColumn(key: "message", label: "Message"),
                TableColumn(key: "author", label: "Author"),
                TableColumn(key: "date", label: "Date")
            ],
            rows: [
                ["abc123", "Initial commit", "John Doe", "2024-01-15"],
                ["def456", "Add feature X", "Jane Smith", "2024-01-16"],
                ["ghi789", "Fix bug in Y", "Bob Johnson", "2024-01-17"],
                ["jkl012", "Update docs", "Alice Brown", "2024-01-18"],
                ["mno345", "Refactor code", "Charlie Davis", "2024-01-19"]
            ]
        )
        
        return VStack(spacing: 20) {
            TableComponent(data: data, isLoading: false)
            TableComponent(data: nil, isLoading: true)
        }
        .padding(20)
        .frame(width: 700)
    }
}
#endif
