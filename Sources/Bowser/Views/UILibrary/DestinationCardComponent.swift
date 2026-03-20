//
//  DestinationCardComponent.swift
//  Bowser
//
//  Compact card for displaying destination information
//

import SwiftUI

// =============================================================================
// MARK: - Destination Card Data Model
// =============================================================================

/// Data model for destination cards
struct DestinationCardData: Codable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let badge: String
    let badgeLabel: String
    
    init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String,
        badge: String,
        badgeLabel: String = "Ideal stay"
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.badgeLabel = badgeLabel
    }
}

// =============================================================================
// MARK: - Destination Card Component
// =============================================================================

/// Compact card showing destination information
struct DestinationCardComponent: View {
    
    let data: DestinationCardData?
    let isLoading: Bool
    
    var body: some View {
        if isLoading {
            skeletonLoader
        } else if let data = data {
            loadedCard(data: data)
        } else {
            emptyState
        }
    }
    
    // MARK: - Skeleton Loader
    
    private var skeletonLoader: some View {
        HStack(spacing: 12) {
            // Icon skeleton
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 32, height: 32)
                .shimmer()
            
            VStack(alignment: .leading, spacing: 6) {
                // Title skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 80, height: 14)
                    .shimmer()
                
                // Subtitle skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 120, height: 10)
                    .shimmer()
            }
            
            Spacer()
            
            // Badge skeleton
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 60, height: 36)
                .shimmer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }
    
    // MARK: - Loaded Card
    
    private func loadedCard(data: DestinationCardData) -> some View {
        HStack(spacing: 12) {
            // Icon
            Circle()
                .fill(Color.blue.opacity(0.1))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                )
            
            // Title and subtitle
            VStack(alignment: .leading, spacing: 4) {
                Text(data.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text(data.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Badge
            VStack(spacing: 2) {
                Text(data.badge)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                
                Text(data.badgeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        HStack {
            Image(systemName: "map")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No destination data")
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
struct DestinationCardComponent_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Loading state
            VStack(alignment: .leading) {
                Text("Loading State")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DestinationCardComponent(data: nil, isLoading: true)
            }
            
            // Loaded state - Matera
            VStack(alignment: .leading) {
                Text("Loaded State - Matera")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DestinationCardComponent(
                    data: DestinationCardData(
                        title: "Matera",
                        subtitle: "Italy · Cave city",
                        badge: "2-3 days",
                        badgeLabel: "Ideal stay"
                    ),
                    isLoading: false
                )
            }
            
            // Loaded state - Mostar
            VStack(alignment: .leading) {
                Text("Loaded State - Mostar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .padding()
        .frame(width: 400)
    }
}
#endif
