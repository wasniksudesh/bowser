// HistoryView.swift - Chrome-style per-folder browsing history

import SwiftUI

// =============================================================================
// MARK: - History View
// =============================================================================

/// Displays the browsing history for the current folder.
/// Shown in the sidebar when the user clicks the History button.
/// Chrome-style layout: grouped by date, searchable, click-to-navigate.
struct HistoryView: View {

    @Bindable var browserState: BrowserState

    @State private var historyItems: [BrowsingHistoryItem] = []
    @State private var searchText: String = ""
    @State private var showingClearConfirm = false

    private var folderId: UUID? { browserState.currentFolderId }

    // MARK: - Filtered & Grouped

    private var filteredItems: [BrowsingHistoryItem] {
        guard !searchText.isEmpty else { return historyItems }
        let q = searchText.lowercased()
        return historyItems.filter {
            $0.displayTitle.lowercased().contains(q) ||
            $0.url.lowercased().contains(q) ||
            ($0.domain?.lowercased().contains(q) ?? false)
        }
    }

    /// Group items by calendar day (today, yesterday, older)
    private var groupedItems: [(label: String, items: [BrowsingHistoryItem])] {
        let calendar = Calendar.current
        let now = Date()

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEEE"

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"

        var todayItems: [BrowsingHistoryItem] = []
        var yesterdayItems: [BrowsingHistoryItem] = []
        var olderBuckets: [String: [BrowsingHistoryItem]] = [:]
        var olderKeys: [String] = []

        for item in filteredItems {
            if calendar.isDateInToday(item.timestamp) {
                todayItems.append(item)
            } else if calendar.isDateInYesterday(item.timestamp) {
                yesterdayItems.append(item)
            } else {
                let daysAgo = calendar.dateComponents([.day], from: item.timestamp, to: now).day ?? 0
                let key = daysAgo < 7
                    ? weekdayFormatter.string(from: item.timestamp)
                    : monthFormatter.string(from: item.timestamp)
                if olderBuckets[key] == nil {
                    olderBuckets[key] = []
                    olderKeys.append(key)
                }
                olderBuckets[key]?.append(item)
            }
        }

        var result: [(label: String, items: [BrowsingHistoryItem])] = []
        if !todayItems.isEmpty { result.append((label: "Today", items: todayItems)) }
        if !yesterdayItems.isEmpty { result.append((label: "Yesterday", items: yesterdayItems)) }
        for key in olderKeys {
            if let items = olderBuckets[key] { result.append((label: key, items: items)) }
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            historyHeader

            // Search bar
            searchBar

            Divider()

            if historyItems.isEmpty {
                emptyState
            } else if filteredItems.isEmpty {
                noResultsState
            } else {
                historyList
            }
        }
        .task {
            reloadHistory()
        }
        .confirmationDialog(
            "Clear History",
            isPresented: $showingClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear All History", role: .destructive) {
                clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all browsing history for this folder.")
        }
    }

    // MARK: - Header

    private var historyHeader: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("History")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            if !historyItems.isEmpty {
                Button {
                    showingClearConfirm = true
                } label: {
                    Text("Clear")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Search history", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - History List

    private var historyList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedItems, id: \.label) { group in
                    Section {
                        ForEach(group.items) { item in
                            HistoryRowView(item: item) {
                                navigate(to: item)
                            } onDelete: {
                                deleteItem(item)
                            }
                        }
                    } header: {
                        Text(group.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial)
                    }
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No History Yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Pages you visit will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No results for \"\(searchText)\"")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: - Actions

    private func navigate(to item: BrowsingHistoryItem) {
        guard let url = URL(string: item.url) else { return }
        browserState.navigateToURL(url)
    }

    private func deleteItem(_ item: BrowsingHistoryItem) {
        historyItems.removeAll { $0.id == item.id }
        if let folderId {
            FolderHistoryPersistence.shared.saveFullHistory(historyItems, forFolder: folderId)
        }
    }

    private func clearHistory() {
        historyItems = []
        if let folderId {
            FolderHistoryPersistence.shared.clearHistory(forFolder: folderId)
        }
    }

    private func reloadHistory() {
        guard let folderId else {
            historyItems = []
            return
        }
        historyItems = FolderHistoryPersistence.shared.loadHistory(forFolder: folderId)
    }
}

// =============================================================================
// MARK: - History Row View
// =============================================================================

private struct HistoryRowView: View {

    let item: BrowsingHistoryItem
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: item.iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(item.domain ?? item.url)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                Text(relativeTime(item.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .monospacedDigit()

                if isHovering {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .background(
                                Circle()
                                    .fill(Color.primary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                Color.primary.opacity(isHovering ? 0.05 : 0.0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}
