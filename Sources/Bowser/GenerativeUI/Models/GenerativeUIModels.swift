//
//  GenerativeUIModels.swift
//  Bowser
//
//  Data models for the generative UI streaming system.
//  These were previously embedded in PlanState.swift.
//

import Foundation

// =============================================================================
// MARK: - Layout Models
// =============================================================================

struct ComponentPosition: Codable {
    let row: Int
    let col: Int
}

struct ComponentSize: Codable {
    let width: Double   // 0.0 to 1.0
    let height: String  // "auto", "small", "medium", "large"
}

struct UIComponentSpec: Codable, Identifiable {
    let id: String
    let type: String
    let position: ComponentPosition
    let size: ComponentSize
    let dataPrompt: String
    /// Per-instance data source, overrides the registry default.
    /// Values: "llm" | "api". If nil, the registry default is used.
    var dataSource: String? = nil
}

struct GenerativeUILayout: Codable {
    let components: [UIComponentSpec]
}

// =============================================================================
// MARK: - SSE Event Types
// =============================================================================

/// Typed representation of SSE events emitted by POST /api/generative-ui/stream
enum GenerativeUIEvent {
    /// Layout skeleton received — Swift should render loading skeletons for all components
    case plan(GenerativeUILayout)
    /// One component's data is ready — Swift renders the component
    case componentData(id: String, data: Any)
    /// A component failed to resolve
    case componentError(id: String, message: String)
    /// All components resolved — stream is done
    case done
    /// Fatal stream-level error
    case streamError(message: String)
}

// =============================================================================
// MARK: - SSE Event Parsing
// =============================================================================

extension GenerativeUIEvent {
    /// Parse a raw SSE line pair (event type + data JSON) into a typed event.
    static func parse(eventType: String, jsonString: String) -> GenerativeUIEvent? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        switch eventType {
        case "plan":
            // Decode GenerativeUILayout from the json payload
            guard let layoutData = try? JSONSerialization.data(withJSONObject: json),
                  let layout = try? JSONDecoder().decode(GenerativeUILayout.self, from: layoutData)
            else { return nil }
            return .plan(layout)

        case "component_data":
            guard let componentId = json["componentId"] as? String,
                  let componentData = json["data"]
            else { return nil }
            return .componentData(id: componentId, data: componentData)

        case "error":
            if let componentId = json["componentId"] as? String {
                return .componentError(id: componentId, message: json["message"] as? String ?? "Unknown error")
            }
            return .streamError(message: json["message"] as? String ?? "Unknown error")

        case "done":
            return .done

        default:
            return nil
        }
    }
}
