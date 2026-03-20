//
//  ListComponent.swift
//  Bowser
//
//  Simple key-value or bullet list component
//  Part of UILibrary for agent output rendering
//

import SwiftUI

// =============================================================================
// MARK: - List Data Models
// =============================================================================

struct ListItem: Identifiable {
    let id: UUID
    let label: String
    let value: String?
    
    init(id: UUID = UUID(), label: String, value: String? = nil) {
        self.id = id
        self.label = label
        self.value = value
    }
}

struct ListData {
    let items: [ListItem]
}

// =============================================================================
// MARK: - List Component
// =============================================================================

/// Simple key-value or bullet list for structured output
struct ListComponent: View {
    
    let data: ListData?
    let isLoading: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                loadingState
            } else if let data = data {
                listContent(data: data)
            } else {
                emptyState
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }
    
    // MARK: - List Content
    
    private func listContent(data: ListData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(data.items) { item in
                    listItemRow(item: item)
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 400)
    }
    
    // MARK: - List Item Row
    
    private func listItemRow(item: ListItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Bullet or key
            if let value = item.value {
                // Key-value pair
                Text(item.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 100, alignment: .leading)
                
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Bullet list
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
                
                Text(item.label)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Loading State
    
    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            
            Text("Loading list...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("No items")
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
struct ListComponent_Previews: PreviewProvider {
    static var previews: some View {
        // Key-value list
        let kvData = ListData(items: [
            ListItem(label: "Repository", value: "octocat/hello-world"),
            ListItem(label: "Branch", value: "main"),
            ListItem(label: "Commits", value: "5"),
            ListItem(label: "Author", value: "John Doe")
        ])
        
        // Bullet list
        let bulletData = ListData(items: [
            ListItem(label: "Initial commit with project structure"),
            ListItem(label: "Added authentication module"),
            ListItem(label: "Fixed bug in user registration"),
            ListItem(label: "Updated documentation"),
            ListItem(label: "Refactored database layer")
        ])
        
        return VStack(spacing: 20) {
            Text("Key-Value List")
                .font(.headline)
            ListComponent(data: kvData, isLoading: false)
            
            Text("Bullet List")
                .font(.headline)
            ListComponent(data: bulletData, isLoading: false)
        }
        .padding(20)
        .frame(width: 600)
    }
}
#endif
