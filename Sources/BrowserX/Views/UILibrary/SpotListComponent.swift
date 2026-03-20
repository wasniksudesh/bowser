//
//  SpotListComponent.swift
//  Bowser
//
//  Vertical list of spots/locations with descriptions
//

import Foundation
import SwiftUI
import os

// =============================================================================
// MARK: - Spot Data Model
// =============================================================================

/// Data model for a spot/location
struct SpotData: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let url: String?

    init(id: String = UUID().uuidString, name: String, description: String, url: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.url = url
    }
}

// =============================================================================
// MARK: - Spot Detail Data Models
// =============================================================================

/// Detailed information about a spot shown in expanded view
struct SpotDetailData: Codable {
    let images: [CarouselImageData]
    let summary: String
    let rating: Double?
    let reviewCount: Int?
    let reviewSnippets: [ReviewSnippet]?
    let citations: [Citation]
}

/// Review snippet from a user
struct ReviewSnippet: Codable, Identifiable {
    let id: String
    let text: String
    let author: String?
    let rating: Double?

    init(id: String = UUID().uuidString, text: String, author: String? = nil, rating: Double? = nil)
    {
        self.id = id
        self.text = text
        self.author = author
        self.rating = rating
    }
}

/// Citation source for information
struct Citation: Codable, Identifiable {
    let id: String
    let title: String
    let url: String
    let section: String

    init(id: String = UUID().uuidString, title: String, url: String, section: String) {
        self.id = id
        self.title = title
        self.url = url
        self.section = section
    }
}

/// API Response for spot detail fetch
struct SpotDetailAPIResponse: Codable {
    let spotId: String
    let data: [String: Any]?
    let success: Bool
    let error: String?

    enum CodingKeys: String, CodingKey {
        case spotId, data, success, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spotId = try container.decode(String.self, forKey: .spotId)
        success = try container.decode(Bool.self, forKey: .success)
        error = try container.decodeIfPresent(String.self, forKey: .error)

        // Decode data as raw JSON and convert to dictionary
        if let dataContainer = try? container.nestedContainer(
            keyedBy: JSONCodingKeys.self, forKey: .data)
        {
            data = try dataContainer.decode([String: Any].self)
        } else {
            data = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(spotId, forKey: .spotId)
        try container.encode(success, forKey: .success)
        try container.encodeIfPresent(error, forKey: .error)
        if let data = data {
            var dataContainer = container.nestedContainer(
                keyedBy: JSONCodingKeys.self, forKey: .data)
            try dataContainer.encode(data)
        }
    }
}

// Helper for dynamic JSON keys
private struct JSONCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer where K == JSONCodingKeys {
    fileprivate func decode(_ type: [String: Any].Type) throws -> [String: Any] {
        var dictionary = [String: Any]()

        for key in allKeys {
            if let boolValue = try? decode(Bool.self, forKey: key) {
                dictionary[key.stringValue] = boolValue
            } else if let intValue = try? decode(Int.self, forKey: key) {
                dictionary[key.stringValue] = intValue
            } else if let doubleValue = try? decode(Double.self, forKey: key) {
                dictionary[key.stringValue] = doubleValue
            } else if let stringValue = try? decode(String.self, forKey: key) {
                dictionary[key.stringValue] = stringValue
            } else if let nestedDict = try? nestedContainer(
                keyedBy: JSONCodingKeys.self, forKey: key
            ).decode([String: Any].self) {
                dictionary[key.stringValue] = nestedDict
            } else if let nestedArray = try? decode([Any].self, forKey: key) {
                dictionary[key.stringValue] = nestedArray
            }
        }

        return dictionary
    }

    fileprivate func decode(_ type: [Any].Type, forKey key: K) throws -> [Any] {
        var container = try nestedUnkeyedContainer(forKey: key)
        return try container.decode([Any].self)
    }
}

extension UnkeyedDecodingContainer {
    fileprivate mutating func decode(_ type: [Any].Type) throws -> [Any] {
        var array = [Any]()

        while !isAtEnd {
            if let boolValue = try? decode(Bool.self) {
                array.append(boolValue)
            } else if let intValue = try? decode(Int.self) {
                array.append(intValue)
            } else if let doubleValue = try? decode(Double.self) {
                array.append(doubleValue)
            } else if let stringValue = try? decode(String.self) {
                array.append(stringValue)
            } else if let nestedDict = try? nestedContainer(keyedBy: JSONCodingKeys.self).decode(
                [String: Any].self)
            {
                array.append(nestedDict)
            } else if var nestedArray = try? nestedUnkeyedContainer() {
                array.append(try nestedArray.decode([Any].self))
            }
        }

        return array
    }
}

extension KeyedEncodingContainer where K == JSONCodingKeys {
    fileprivate mutating func encode(_ value: [String: Any]) throws {
        for (key, val) in value {
            let codingKey = JSONCodingKeys(stringValue: key)!
            switch val {
            case let boolValue as Bool:
                try encode(boolValue, forKey: codingKey)
            case let intValue as Int:
                try encode(intValue, forKey: codingKey)
            case let doubleValue as Double:
                try encode(doubleValue, forKey: codingKey)
            case let stringValue as String:
                try encode(stringValue, forKey: codingKey)
            case let dictValue as [String: Any]:
                var nestedContainer = nestedContainer(
                    keyedBy: JSONCodingKeys.self, forKey: codingKey)
                try nestedContainer.encode(dictValue)
            case let arrayValue as [Any]:
                var nestedContainer = nestedUnkeyedContainer(forKey: codingKey)
                try nestedContainer.encode(arrayValue)
            default:
                break
            }
        }
    }
}

extension UnkeyedEncodingContainer {
    fileprivate mutating func encode(_ value: [Any]) throws {
        for val in value {
            switch val {
            case let boolValue as Bool:
                try encode(boolValue)
            case let intValue as Int:
                try encode(intValue)
            case let doubleValue as Double:
                try encode(doubleValue)
            case let stringValue as String:
                try encode(stringValue)
            case let dictValue as [String: Any]:
                var nestedContainer = nestedContainer(keyedBy: JSONCodingKeys.self)
                try nestedContainer.encode(dictValue)
            case let arrayValue as [Any]:
                var nestedContainer = nestedUnkeyedContainer()
                try nestedContainer.encode(arrayValue)
            default:
                break
            }
        }
    }
}

// =============================================================================
// MARK: - Spot List Component
// =============================================================================

/// Vertical list of spots with circular indicators
struct SpotListComponent: View {

    let spots: [SpotData]
    let isLoading: Bool
    let title: String?
    let browserState: BrowserState?

    @State private var expandedSpotId: String? = nil
    @State private var spotDetailsCache: [String: SpotDetailData] = [:]
    @State private var loadingDetailSpotIds: Set<String> = []
    @Namespace private var animation

    private let logger = Logger(subsystem: "com.bowser.ui", category: "SpotListComponent")

    init(
        spots: [SpotData] = [], isLoading: Bool = false, title: String? = nil,
        browserState: BrowserState? = nil
    ) {
        self.spots = spots
        self.isLoading = isLoading
        self.title = title
        self.browserState = browserState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            if isLoading {
                skeletonLoader
            } else if !spots.isEmpty {
                loadedList
            } else {
                emptyState
            }
        }
    }

    // MARK: - Skeleton Loader

    private var skeletonLoader: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                spotSkeletonRow
            }
        }
    }

    private var spotSkeletonRow: some View {
        HStack(alignment: .top, spacing: 12) {
            // Circle skeleton
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 24, height: 24)
                .shimmer()

            VStack(alignment: .leading, spacing: 6) {
                // Name skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 140, height: 14)
                    .shimmer()

                // Description skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 200, height: 10)
                    .shimmer()
            }

            Spacer()
        }
    }

    // MARK: - Loaded List

    private var loadedList: some View {
        VStack(spacing: 12) {
            ForEach(spots) { spot in
                VStack(spacing: 0) {
                    spotRow(spot: spot)

                    // Expanded detail panel
                    if expandedSpotId == spot.id {
                        expandedDetailPanel(for: spot)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(
                                        with: .scale(scale: 0.95, anchor: .top)),
                                    removal: .opacity
                                ))
                    }
                }
            }
        }
    }

    private func spotRow(spot: SpotData) -> some View {
        Button(action: {
            toggleSpotExpansion(spot: spot)
        }) {
            spotRowContent(spot: spot, isExpanded: expandedSpotId == spot.id)
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }

    private func toggleSpotExpansion(spot: SpotData) {
        withAnimation(.easeInOut(duration: 0.3)) {
            if expandedSpotId == spot.id {
                // Collapse
                expandedSpotId = nil
            } else {
                // Expand
                expandedSpotId = spot.id

                // Fetch details if not cached
                if spotDetailsCache[spot.id] == nil && !loadingDetailSpotIds.contains(spot.id) {
                    Task {
                        await fetchSpotDetails(spot: spot)
                    }
                }
            }
        }
    }

    private func spotRowContent(spot: SpotData, isExpanded: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Circular indicator with expand icon - ALWAYS VISIBLE
            ZStack {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 2)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .fill(isExpanded ? Color.blue.opacity(0.3) : Color.clear)
                            .frame(width: 20, height: 20)
                    )

                // Plus/minus icon in the circle - ALWAYS VISIBLE
                Image(systemName: isExpanded ? "minus" : "plus")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(isExpanded ? .blue : .primary)
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }

            // Spot info
            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .matchedGeometryEffect(id: "name-\(spot.id)", in: animation)

                Text(spot.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Expand/collapse chevron (more prominent) - ALWAYS VISIBLE
            Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isExpanded ? .blue : .secondary)
                .animation(.easeInOut(duration: 0.3), value: isExpanded)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isExpanded ? Color.blue.opacity(0.08) : Color.clear)
        )
    }

    // MARK: - Expanded Detail Panel

    @ViewBuilder
    private func expandedDetailPanel(for spot: SpotData) -> some View {
        let isLoadingDetails = loadingDetailSpotIds.contains(spot.id)
        let details = spotDetailsCache[spot.id]

        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.vertical, 12)

            if isLoadingDetails {
                detailPanelSkeleton
            } else if let details = details {
                detailPanelContent(spot: spot, details: details)
            } else {
                detailPanelError
            }
        }
    }

    // MARK: - Detail Panel Skeleton

    private var detailPanelSkeleton: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Image carousel skeleton
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(height: 200)
                .shimmer()

            // Header skeleton
            HStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 120, height: 14)
                    .shimmer()
                Spacer()
            }

            // Summary skeleton
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(height: 10)
                        .shimmer()
                }
            }

            // Reviews skeleton
            VStack(spacing: 12) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .frame(height: 60)
                        .shimmer()
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.2))
        )
    }

    // MARK: - Detail Panel Content

    private func detailPanelContent(spot: SpotData, details: SpotDetailData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Image carousel
            if !details.images.isEmpty {
                CarouselComponent(images: details.images, isLoading: false)
            }

            // Header with rating
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(spot.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Spacer()

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            expandedSpotId = nil
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Rating bar
                if let rating = details.rating {
                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            ForEach(0..<5) { index in
                                Image(
                                    systemName: index < Int(rating.rounded()) ? "star.fill" : "star"
                                )
                                .font(.system(size: 12))
                                .foregroundStyle(.yellow)
                            }
                        }

                        Text(String(format: "%.1f", rating))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        if let reviewCount = details.reviewCount {
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text("\(formatNumber(reviewCount)) reviews")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            // Summary section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Summary")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Spacer()

                    // Citation indicators
                    HStack(spacing: 4) {
                        ForEach(details.citations.filter { $0.section == "summary" }) { citation in
                            citationBadge(citation: citation)
                        }
                    }
                }

                Text(details.summary)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Reviews section
            if let reviews = details.reviewSnippets, !reviews.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Reviews")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Spacer()

                        // Citation indicators
                        HStack(spacing: 4) {
                            ForEach(details.citations.filter { $0.section == "reviews" }) {
                                citation in
                                citationBadge(citation: citation)
                            }
                        }
                    }

                    ForEach(reviews.prefix(3)) { review in
                        reviewCard(review: review)
                    }
                }
            }

            // Sources/Citations section
            if !details.citations.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Sources")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(details.citations.enumerated()), id: \.element.id) {
                            index, citation in
                            citationRow(citation: citation, index: index + 1)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Detail Panel Helpers

    private func citationBadge(citation: Citation) -> some View {
        Button(action: {
            if let url = URL(string: citation.url), let browserState = browserState {
                _ = browserState.createTab(url: url)
            }
        }) {
            Text("[\(citation.id.prefix(1))]")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.blue.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .help(citation.title)
    }

    private func reviewCard(review: ReviewSnippet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let rating = review.rating {
                    HStack(spacing: 2) {
                        ForEach(0..<5) { index in
                            Image(systemName: index < Int(rating.rounded()) ? "star.fill" : "star")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                        }
                    }
                }

                if let author = review.author {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Text(review.text)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }

    private func citationRow(citation: Citation, index: Int) -> some View {
        Button(action: {
            if let url = URL(string: citation.url), let browserState = browserState {
                _ = browserState.createTab(url: url)
            }
        }) {
            HStack(spacing: 8) {
                Text("[\(index)]")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(citation.title)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(citation.url)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var detailPanelError: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("Failed to load details")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.2))
        )
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }

    // MARK: - API Integration

    private func fetchSpotDetails(spot: SpotData) async {
        loadingDetailSpotIds.insert(spot.id)

        do {
            guard
                let url = URL(
                    string: "http://localhost:8765/api/generative-ui/resolve-spot-details")
            else {
                throw URLError(.badURL)
            }

            let requestBody: [String: Any] = [
                "spotId": spot.id,
                "spotName": spot.name,
                "spotDescription": spot.description,
                "leafContext": [
                    "title": "Top Spots",
                    "description": "",
                ],
            ]

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                throw URLError(.badServerResponse)
            }

            let decoder = JSONDecoder()
            let apiResponse = try decoder.decode(SpotDetailAPIResponse.self, from: data)

            if apiResponse.success, let detailData = apiResponse.data {
                // Parse detail data
                let images =
                    (detailData["images"] as? [[String: Any]])?.compactMap {
                        dict -> CarouselImageData? in
                        guard let url = dict["url"] as? String else { return nil }
                        let caption = dict["caption"] as? String
                        let id = dict["id"] as? String ?? UUID().uuidString
                        return CarouselImageData(id: id, url: url, caption: caption)
                    } ?? []

                let summary = detailData["summary"] as? String ?? ""
                let rating = detailData["rating"] as? Double
                let reviewCount = detailData["reviewCount"] as? Int

                let reviewSnippets = (detailData["reviewSnippets"] as? [[String: Any]])?.compactMap
                { dict -> ReviewSnippet? in
                    guard let text = dict["text"] as? String else { return nil }
                    let id = dict["id"] as? String ?? UUID().uuidString
                    let author = dict["author"] as? String
                    let rating = dict["rating"] as? Double
                    return ReviewSnippet(id: id, text: text, author: author, rating: rating)
                }

                let citations =
                    (detailData["citations"] as? [[String: Any]])?.compactMap { dict -> Citation? in
                        guard let title = dict["title"] as? String,
                            let url = dict["url"] as? String,
                            let section = dict["section"] as? String
                        else { return nil }
                        let id = dict["id"] as? String ?? UUID().uuidString
                        return Citation(id: id, title: title, url: url, section: section)
                    } ?? []

                let spotDetails = SpotDetailData(
                    images: images,
                    summary: summary,
                    rating: rating,
                    reviewCount: reviewCount,
                    reviewSnippets: reviewSnippets,
                    citations: citations
                )

                spotDetailsCache[spot.id] = spotDetails
            }

        } catch {
            logger.error(
                "Failed to fetch spot details: \(error.localizedDescription, privacy: .public)")
        }

        loadingDetailSpotIds.remove(spot.id)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No spots available")
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
    struct SpotListComponent_Previews: PreviewProvider {
        static var previews: some View {
            VStack(spacing: 30) {
                // Loading state
                VStack(alignment: .leading) {
                    Text("Loading State")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SpotListComponent(isLoading: true, title: "Top Spots")
                }

                // Loaded state with Matera spots
                VStack(alignment: .leading) {
                    Text("Loaded State - Matera")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SpotListComponent(
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
                        ],
                        isLoading: false,
                        title: "Top Spots"
                    )
                }
            }
            .padding()
            .frame(width: 400)
        }
    }
#endif
