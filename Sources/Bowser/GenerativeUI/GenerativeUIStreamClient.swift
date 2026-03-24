//
//  GenerativeUIStreamClient.swift
//  Bowser
//
//  SSE client for the generative UI streaming endpoint.
//  Opens a persistent connection to POST /api/generative-ui/stream and
//  updates PlanState as each SSE event arrives.
//
//  Modeled on the existing SSE pattern in AgentState.streamEvents().
//

import Foundation

// =============================================================================
// MARK: - Generative UI Stream Client
// =============================================================================

/// Manages the SSE connection to the generative UI stream endpoint.
/// Writes directly to @Observable PlanState so SwiftUI re-renders
/// progressively as each component resolves.
@MainActor
final class GenerativeUIStreamClient {

    private let baseURL = URL(string: "http://localhost:8765/api/generative-ui/stream")!

    // MARK: - Public Entry Point

    /// Opens an SSE stream for the given leaf node and updates planState
    /// as plan and component_data events arrive.
    func streamLayout(for node: PlanNode, planState: PlanState) async {
        planState.isLoading = true
        planState.errorMessage = nil
        planState.generativeUILayout = nil
        planState.componentDataCache = [:]
        planState.loadingComponentIds = []

        do {
            let request = try buildRequest(for: node)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                planState.errorMessage = "Failed to connect to generative UI stream"
                planState.isLoading = false
                return
            }

            var currentEventType: String? = nil

            for try await line in bytes.lines {
                // SSE keepalive comments — ignore
                if line.hasPrefix(":") { continue }

                if line.hasPrefix("event: ") {
                    currentEventType = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                    continue
                }

                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    let eventType = currentEventType ?? "unknown"
                    currentEventType = nil

                    if let event = GenerativeUIEvent.parse(eventType: eventType, jsonString: jsonString) {
                        handle(event: event, planState: planState)
                    }
                }
            }

        } catch {
            planState.errorMessage = "Stream error: \(error.localizedDescription)"
            planState.isLoading = false
        }
    }

    // MARK: - Event Handler

    private func handle(event: GenerativeUIEvent, planState: PlanState) {
        switch event {
        case .plan(let layout):
            planState.generativeUILayout = layout
            // Mark all components as loading so skeletons appear immediately
            let allIds = Set(layout.components.map(\.id))
            planState.loadingComponentIds = allIds

        case .componentData(let id, let data):
            planState.componentDataCache[id] = data
            planState.loadingComponentIds.remove(id)

        case .componentError(let id, _):
            // Remove from loading so the component shows its error/empty state
            planState.loadingComponentIds.remove(id)

        case .done:
            planState.isLoading = false
            planState.loadingComponentIds = []

        case .streamError(let message):
            planState.errorMessage = message
            planState.isLoading = false
            planState.loadingComponentIds = []
        }
    }

    // MARK: - Request Builder

    private func buildRequest(for node: PlanNode) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120  // Long timeout for streaming

        let leafContext: [String: Any] = [
            "title": node.title,
            "description": node.description ?? "",
            "links": node.links.map { ["title": $0.title, "url": $0.url.absoluteString] },
        ]

        let availableComponents = UIComponentRegistry.components.map { component in
            [
                "type": component.type.rawValue,
                "displayName": component.displayName,
                "description": component.description,
                "compatibleDataTypes": component.compatibleDataTypes,
                "sizeHint": component.sizeHint,
                "dataSource": component.dataSource,
                "supportedDataSources": component.supportedDataSources,
            ] as [String: Any]
        }

        let body: [String: Any] = [
            "leafContext": leafContext,
            "availableComponents": availableComponents,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
