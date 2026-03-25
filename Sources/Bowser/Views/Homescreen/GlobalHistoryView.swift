// GlobalHistoryView.swift - Cross-folder browsing history for the homescreen sidebar

import SwiftUI

// =============================================================================
// MARK: - Global History View
// =============================================================================

/// Displays aggregated browsing history across all folders.
/// Shown in the homescreen left sidebar. Supports search and click-to-open-in-folder.
struct GlobalHistoryView: View {

    @Bindable var browserState: BrowserState
    @Bindable var appNav: AppNavigationState
    @Binding var searchText: String

    @State private var allEntries: [GlobalHistoryEntry] = []

    private var folders: [Folder] { browserState.folderManager.sortedFolders }

    // MARK: - Filtered & Grouped

    private var filteredEntries: [GlobalHistoryEntry] {
        guard !searchText.isEmpty else { return allEntries }
        let q = searchText.lowercased()
        return allEntries.filter {
            $0.item.displayTitle.lowercased().contains(q) ||
            $0.item.url.lowercased().contains(q) ||
            ($0.item.domain?.lowercased().contains(q) ?? false) ||
            $0.folderName.lowercased().contains(q)
        }
    }

    private var groupedEntries: [(label: String, entries: [GlobalHistoryEntry])] {
        let calendar = Calendar.current
        let now = Date()

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEEE"

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"

        var todayItems: [GlobalHistoryEntry] = []
        var yesterdayItems: [GlobalHistoryEntry] = []
        var olderBuckets: [String: [GlobalHistoryEntry]] = [:]
        var olderKeys: [String] = []

        for entry in filteredEntries {
            if calendar.isDateInToday(entry.item.timestamp) {
                todayItems.append(entry)
            } else if calendar.isDateInYesterday(entry.item.timestamp) {
                yesterdayItems.append(entry)
            } else {
                let daysAgo = calendar.dateComponents([.day], from: entry.item.timestamp, to: now).day ?? 0
                let key = daysAgo < 7
                    ? weekdayFormatter.string(from: entry.item.timestamp)
                    : monthFormatter.string(from: entry.item.timestamp)
                if olderBuckets[key] == nil {
                    olderBuckets[key] = []
                    olderKeys.append(key)
                }
                olderBuckets[key]?.append(entry)
            }
        }

        var result: [(label: String, entries: [GlobalHistoryEntry])] = []
        if !todayItems.isEmpty { result.append((label: "Today", entries: todayItems)) }
        if !yesterdayItems.isEmpty { result.append((label: "Yesterday", entries: yesterdayItems)) }
        for key in olderKeys {
            if let items = olderBuckets[key] { result.append((label: key, entries: items)) }
        }
        return result
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if allEntries.isEmpty {
                emptyState
            } else if filteredEntries.isEmpty {
                noResultsState
            } else {
                historyList
            }
        }
        .task {
            reloadHistory()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("History")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text("\(allEntries.count)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - History List

    private var historyList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedEntries, id: \.label) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            GlobalHistoryRowView(entry: entry) {
                                openInFolder(entry)
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
            Text("Pages you visit in any folder\nwill appear here.")
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

    private func openInFolder(_ entry: GlobalHistoryEntry) {
        appNav.openFolder(entry.folderId)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            browserState.loadFolder(id: entry.folderId)
            if let url = URL(string: entry.item.url) {
                try? await Task.sleep(for: .milliseconds(100))
                browserState.navigateToURL(url)
            }
        }
    }

    private func reloadHistory() {
        allEntries = FolderHistoryPersistence.shared.loadAllHistory(folders: folders)
    }
}

// =============================================================================
// MARK: - Global History Row View
// =============================================================================

private struct GlobalHistoryRowView: View {

    let entry: GlobalHistoryEntry
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: entry.item.iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.item.displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(entry.item.domain ?? entry.item.url)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(relativeTime(entry.item.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                        .monospacedDigit()

                    // Folder badge
                    HStack(spacing: 3) {
                        Circle()
                            .fill(entry.folderColor)
                            .frame(width: 6, height: 6)
                        Text(entry.folderName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
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
