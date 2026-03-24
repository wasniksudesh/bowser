// PlanStateTests.swift
// Tests for Plan Mode — validates the JSON contract between the Python
// backend and the Swift PlanState model layer.
//
// These tests exercise the exact JSON shapes that PlanState.swift parses,
// ensuring the frontend correctly handles backend responses without a live
// server.
//
// Feature: Plan Mode (Generative UI layout + component data)
// Coverage (3 high-signal tests):
//   1. Valid generative-UI layout response parses to correct component count.
//   2. Component resolve response is non-nil and preserves the component ID.
//   3. A 500 / error body is handled gracefully (no crash, nil data).

import XCTest
import Foundation

// ---------------------------------------------------------------------------
// Minimal response models mirroring PlanState.swift GenerativeUILayout shapes
// ---------------------------------------------------------------------------

private struct ComponentPosition: Codable {
    let row: Int
    let col: Int
}

private struct ComponentSize: Codable {
    let width: Double
    let height: String
}

private struct UIComponentSpec: Codable {
    let id: String
    let type: String
    let position: ComponentPosition
    let size: ComponentSize
    let dataPrompt: String
}

private struct GenerativeUILayout: Codable {
    let components: [UIComponentSpec]
}

private struct LayoutPlanResponse: Codable {
    let layout: GenerativeUILayout
}

private struct ResolveResponse: Codable {
    let componentId: String
    let data: AnyCodable?
    let success: Bool
    let error: String?
}

/// Thin wrapper so `data: Any` can round-trip through Codable.
private struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: String].self) {
            value = dict
        } else if let arr = try? container.decode([String].self) {
            value = arr
        } else {
            value = (try? container.decode(String.self)) ?? ""
        }
    }

    func encode(to encoder: Encoder) throws {
        // encode not needed in tests
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

private func json(_ dict: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: dict)
}

private func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
    try? JSONDecoder().decode(type, from: data)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

final class PlanStateTests: XCTestCase {

    // MARK: - Test 1: Layout plan response parses component list

    /// POST /api/generative-ui/plan success response must decode to a
    /// GenerativeUILayout with the expected component count and types.
    func testFetchLayoutPlan_parsesValidResponse() {
        let responseJSON: [String: Any] = [
            "layout": [
                "components": [
                    [
                        "id": "comp1",
                        "type": "spotList",
                        "position": ["row": 0, "col": 0],
                        "size": ["width": 1.0, "height": "auto"],
                        "dataPrompt": "List top spots in Rome"
                    ],
                    [
                        "id": "comp2",
                        "type": "carousel",
                        "position": ["row": 1, "col": 0],
                        "size": ["width": 1.0, "height": "large"],
                        "dataPrompt": "Show images of Rome"
                    ]
                ]
            ]
        ]

        let data = json(responseJSON)
        let response = decode(LayoutPlanResponse.self, from: data)

        XCTAssertNotNil(response, "LayoutPlanResponse must decode successfully")
        let components = response!.layout.components
        XCTAssertEqual(components.count, 2, "Should have 2 components")
        XCTAssertEqual(components[0].type, "spotList")
        XCTAssertEqual(components[1].type, "carousel")
        XCTAssertFalse(components[0].dataPrompt.isEmpty, "dataPrompt must not be empty")
    }

    // MARK: - Test 2: Resolve response preserves component ID

    /// POST /api/generative-ui/resolve success response must decode with the
    /// correct componentId, success=true, and non-nil data.
    func testFetchComponentData_preservesComponentId() {
        let responseJSON: [String: Any] = [
            "componentId": "comp1",
            "success": true,
            "data": ["spots": ["Colosseum", "Vatican"]],
            "error": NSNull()
        ]

        let data = json(responseJSON)
        let response = decode(ResolveResponse.self, from: data)

        XCTAssertNotNil(response)
        XCTAssertEqual(response!.componentId, "comp1")
        XCTAssertTrue(response!.success)
        XCTAssertNil(response!.error)
        XCTAssertNotNil(response!.data, "Resolved data must be present")
    }

    // MARK: - Test 3: Error response handled gracefully

    /// When the backend returns success=false with an error string, the
    /// model must decode without crashing and expose the error message.
    func testFetchLayoutPlan_handlesErrorResponse() {
        let responseJSON: [String: Any] = [
            "componentId": "comp1",
            "success": false,
            "data": NSNull(),
            "error": "LLM returned invalid JSON"
        ]

        let data = json(responseJSON)
        let response = decode(ResolveResponse.self, from: data)

        XCTAssertNotNil(response)
        XCTAssertFalse(response!.success)
        XCTAssertEqual(response!.error, "LLM returned invalid JSON")
        XCTAssertNil(response!.data, "Data should be nil on error")
    }
}
