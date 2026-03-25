// HomescreenSearchState.swift
// Observable model driving the homescreen AI search popup.
// Sends the user query to the generative-ui/plan + resolve endpoints
// and caches layout + component data for rendering.

import Foundation
import Observation

@Observable
@MainActor
final class HomescreenSearchState {

    // MARK: - Published State

    var query: String = ""
    var isSearching: Bool = false
    var showResults: Bool = false

    var generativeUILayout: GenerativeUILayout?
    var componentDataCache: [String: Any] = [:]
    var loadingComponentIds: Set<String> = []
    var errorMessage: String?

    // MARK: - Search

    func submitSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        self.query = trimmed
        showResults = true
        generativeUILayout = nil
        componentDataCache = [:]
        loadingComponentIds = []
        errorMessage = nil
        isSearching = true

        Task { await fetchLayoutPlan() }
    }

    func dismiss() {
        showResults = false
        isSearching = false
        generativeUILayout = nil
        componentDataCache = [:]
        loadingComponentIds = []
        errorMessage = nil
    }

    // MARK: - Generative UI Plan

    private func fetchLayoutPlan() async {
        do {
            let url = URL(string: "http://localhost:8765/api/generative-ui/plan")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 30

            let searchContext: [String: Any] = [
                "title": query,
                "description": "User searched for: \(query)",
                "intent": "search",
            ]

            let availableComponents = UIComponentRegistry.components.map { meta in
                [
                    "type": meta.type.rawValue,
                    "displayName": meta.displayName,
                    "description": meta.description,
                    "compatibleDataTypes": meta.compatibleDataTypes,
                    "expectedDataSchema": meta.expectedDataSchema,
                    "sizeHint": meta.sizeHint,
                ] as [String: Any]
            }

            let body: [String: Any] = [
                "leafContext": searchContext,
                "availableComponents": availableComponents,
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, _) = try await URLSession.shared.data(for: request)

            struct LayoutPlanResponse: Codable {
                let layout: GenerativeUILayout
            }

            let response = try JSONDecoder().decode(LayoutPlanResponse.self, from: data)
            self.generativeUILayout = response.layout

            await fetchAllComponentData()

            isSearching = false
        } catch {
            print("Homescreen search layout plan error: \(error)")
            errorMessage = "Failed to generate search results"
            isSearching = false
        }
    }

    // MARK: - Component Data Resolution

    private func fetchAllComponentData() async {
        guard let layout = generativeUILayout else { return }

        await withTaskGroup(of: Void.self) { group in
            for component in layout.components {
                group.addTask {
                    await self.fetchComponentData(component: component)
                }
            }
        }
    }

    private func fetchComponentData(component: UIComponentSpec) async {
        loadingComponentIds.insert(component.id)

        do {
            let url = URL(string: "http://localhost:8765/api/generative-ui/resolve")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let searchContext: [String: Any] = [
                "title": query,
                "description": "User searched for: \(query)",
            ]

            let body: [String: Any] = [
                "componentId": component.id,
                "componentType": component.type,
                "dataPrompt": component.dataPrompt,
                "leafContext": searchContext,
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, _) = try await URLSession.shared.data(for: request)

            struct ResolveResponse: Codable {
                let componentId: String
                let data: AnyCodable?
                let success: Bool
                let error: String?
            }

            let response = try JSONDecoder().decode(ResolveResponse.self, from: data)

            if response.success, let componentData = response.data?.value {
                componentDataCache[component.id] = componentData
            }

            loadingComponentIds.remove(component.id)
        } catch {
            print("Search component data fetch error for \(component.id): \(error)")
            loadingComponentIds.remove(component.id)
        }
    }
}
