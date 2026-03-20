//
//  HighlightsTabComponent.swift
//  Bowser
//
//  Tabbed interface showing highlights for different destinations
//

import SwiftUI

// =============================================================================
// MARK: - Highlights Data Models
// =============================================================================

/// Tab data for highlights view
struct HighlightTab: Codable, Identifiable {
    let id: String
    let title: String
    let description: String
    let spots: [SpotData]
}

/// Container for all tabs
struct HighlightsData: Codable {
    let sectionTitle: String?
    let tabs: [HighlightTab]

    init(sectionTitle: String? = nil, tabs: [HighlightTab]) {
        self.sectionTitle = sectionTitle
        self.tabs = tabs
    }
}

// =============================================================================
// MARK: - Highlights Tab Component
// =============================================================================

/// Tabbed interface showing highlights by destination
struct HighlightsTabComponent: View {

    let data: HighlightsData?
    let isLoading: Bool

    @State private var selectedTabId: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                skeletonLoader
            } else if let data = data, !data.tabs.isEmpty {
                loadedTabs(data: data)
            } else {
                emptyState
            }
        }
    }

    // MARK: - Skeleton Loader

    private var skeletonLoader: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section title skeleton
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 180, height: 16)
                .shimmer()

            // Tab buttons skeleton
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(width: 60, height: 28)
                        .shimmer()
                }
            }

            // Description skeleton
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(height: 12)
                    .shimmer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 280, height: 12)
                    .shimmer()
            }

            // Spots skeleton
            VStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(width: 24, height: 24)
                            .shimmer()

                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .frame(width: 140, height: 14)
                                .shimmer()
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .frame(width: 200, height: 10)
                                .shimmer()
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }

    // MARK: - Loaded Tabs

    private func loadedTabs(data: HighlightsData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section title (dynamic based on context)
            Text(data.sectionTitle ?? "Highlights")
                .font(.headline)
                .foregroundStyle(.primary)

            // Tab buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(data.tabs) { tab in
                        tabButton(tab: tab, isSelected: selectedTabId == tab.id)
                    }
                }
            }

            // Tab content
            if let selectedTab = data.tabs.first(where: { $0.id == selectedTabId }) {
                tabContent(tab: selectedTab)
            } else if let firstTab = data.tabs.first {
                tabContent(tab: firstTab)
                    .onAppear {
                        selectedTabId = firstTab.id
                    }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }

    private func tabButton(tab: HighlightTab, isSelected: Bool) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTabId = tab.id
            }
        }) {
            Text(tab.title)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.blue : Color(nsColor: .controlBackgroundColor))
                )
        }
        .buttonStyle(.plain)
    }

    private func tabContent(tab: HighlightTab) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Description
            Text(tab.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Divider()
                .padding(.vertical, 4)

            // Spots list
            Text("Top Spots")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(spacing: 12) {
                ForEach(tab.spots) { spot in
                    HStack(alignment: .top, spacing: 12) {
                        // Circular indicator
                        Circle()
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 2)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 20, height: 20)
                            )

                        // Spot info
                        VStack(alignment: .leading, spacing: 4) {
                            Text(spot.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)

                            Text(spot.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.split.2x1")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No highlights available")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
    struct HighlightsTabComponent_Previews: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 30) {
                // Loading state
                VStack(alignment: .leading) {
                    Text("Loading State")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HighlightsTabComponent(data: nil, isLoading: true)
                }

                // Loaded state with mock data
                VStack(alignment: .leading) {
                    Text("Loaded State")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HighlightsTabComponent(
                        data: HighlightsData(tabs: [
                            HighlightTab(
                                id: "matera",
                                title: "Matera",
                                description:
                                    "Ancient cave dwellings (Sassi), cinematic sunsets, and rock-hewn churches. Best at golden hour; pair with Puglia road trip.",
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
                                    ),
                                ]
                            ),
                            HighlightTab(
                                id: "mostar",
                                title: "Mostar",
                                description:
                                    "Iconic Ottoman bridge, cobblestone streets, and Balkan fusion cuisine.",
                                spots: [
                                    SpotData(
                                        name: "Stari Most",
                                        description: "Historic bridge with cliff divers"
                                    ),
                                    SpotData(
                                        name: "Old Bazaar",
                                        description: "Ottoman-era marketplace"
                                    ),
                                ]
                            ),
                            HighlightTab(
                                id: "galle",
                                title: "Galle",
                                description:
                                    "Colonial fort city with Sri Lankan charm and coastal beauty.",
                                spots: [
                                    SpotData(
                                        name: "Galle Fort",
                                        description: "UNESCO World Heritage Site"
                                    )
                                ]
                            ),
                            HighlightTab(
                                id: "lapaz",
                                title: "La Paz",
                                description: "High-altitude adventure and vibrant markets.",
                                spots: [
                                    SpotData(
                                        name: "Witches Market",
                                        description: "Traditional Aymara market"
                                    )
                                ]
                            ),
                        ]),
                        isLoading: false
                    )
                }
            }
            .padding()
            .frame(width: 500)
        }
    }
#endif
