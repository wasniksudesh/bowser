//
//  ArtifactView.swift
//  Bowser
//
//  Full-page view for browsing date-segmented agent artifacts
//  Each date entry is rendered using the appropriate UILibrary component
//

import SwiftUI

// =============================================================================
// MARK: - Artifact Entry
// =============================================================================

struct ArtifactEntryData: Identifiable {
    let id = UUID()
    let date: String
    let data: Any?
}

// =============================================================================
// MARK: - Artifact View
// =============================================================================

/// Full-page viewer for a widget's date-segmented artifact
struct ArtifactView: View {
    
    @Bindable var browserState: BrowserState
    let widgetId: String
    let componentType: String
    @State private var entries: [ArtifactEntryData] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Text("Artifact History")
                    .font(.headline)
                
                Spacer()
                
                Text("\(entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Content
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading artifact...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No entries yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(entries.reversed()) { entry in
                            VStack(alignment: .leading, spacing: 12) {
                                // Date header
                                HStack {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.blue)
                                    Text(entry.date)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                                
                                // Render the entry data using AgentOutputView
                                AgentOutputView(
                                    componentType: componentType,
                                    componentData: entry.data,
                                    summary: "",
                                    compact: false,
                                    browserState: browserState
                                )
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await fetchArtifact()
        }
    }
    
    // MARK: - Fetch
    
    private func fetchArtifact() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let url = URL(string: "http://localhost:8765/api/widgets/\(widgetId)/artifact")!
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                errorMessage = "Failed to load artifact"
                return
            }
            
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let entriesArray = json?["entries"] as? [[String: Any]] else {
                errorMessage = "Invalid artifact format"
                return
            }
            
            entries = entriesArray.map { entry in
                ArtifactEntryData(
                    date: entry["date"] as? String ?? "Unknown",
                    data: entry["data"]
                )
            }
            
            // Mark as read
            let markReadURL = URL(string: "http://localhost:8765/api/widgets/\(widgetId)/artifact/mark-read")!
            var markRequest = URLRequest(url: markReadURL)
            markRequest.httpMethod = "POST"
            _ = try? await URLSession.shared.data(for: markRequest)
        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
        }
    }
}
