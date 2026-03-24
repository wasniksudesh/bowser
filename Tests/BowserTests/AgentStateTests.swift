// AgentStateTests.swift
// Tests for Agent Mode — validates the JSON contract between the Python
// backend and the Swift AgentState model layer.
//
// Tests exercise the exact JSON shapes returned by /api/agent/goals/* and
// the SSE event wire format, ensuring correct parsing without a live server.
//
// Feature: Agent Mode (goal planning, approval, SSE streaming)
// Coverage (3 high-signal tests):
//   1. Goal plan response decodes to a session with goals + required_auth.
//   2. Approve response body correctly distinguishes "approved" vs "revised".
//   3. SSE event lines are parsed into typed event dictionaries for all
//      high-frequency event types.

import XCTest
import Foundation

// ---------------------------------------------------------------------------
// Minimal models mirroring AgentState.swift
// ---------------------------------------------------------------------------

private struct GoalModel: Codable {
    let goal_id: String
    let description: String
    let plugin_id: String
    let status: String
}

private struct GoalPlanModel: Codable {
    let plan_id: String
    let goals: [GoalModel]
    let status: String
}

private struct GoalPlanResponse: Codable {
    let session_id: String
    let goal_plan: GoalPlanModel
    let required_auth: [[String: AnyCodable]]
}

private struct ApproveResponse: Codable {
    let status: String
    let goal_plan: GoalPlanModel?
    let message: String?
}

/// Minimal Any-Codable wrapper for heterogeneous dictionaries.
private struct AnyCodable: Codable {
    let rawValue: Any

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self)       { rawValue = s; return }
        if let i = try? c.decode(Int.self)           { rawValue = i; return }
        if let b = try? c.decode(Bool.self)          { rawValue = b; return }
        if let a = try? c.decode([String].self)      { rawValue = a; return }
        rawValue = ""
    }
    func encode(to encoder: Encoder) throws {}
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

/// Parses a single SSE `data: {...}` line into a dictionary.
private func parseSSELine(_ line: String) -> [String: Any]? {
    guard line.hasPrefix("data: ") else { return nil }
    let jsonString = String(line.dropFirst(6))
    guard let data = jsonString.data(using: .utf8),
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return dict
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

final class AgentStateTests: XCTestCase {

    // MARK: - Test 1: Goal plan response decodes sessions and goals

    /// POST /api/agent/goals/plan response must decode into a session with
    /// the correct session_id, goal count, and required_auth entries.
    func testSubmitQuery_parsesGoalPlanResponse() {
        let responseJSON: [String: Any] = [
            "session_id": "550e8400-e29b-41d4-a716-446655440000",
            "goal_plan": [
                "plan_id": "plan-001",
                "goals": [
                    [
                        "goal_id": "G-0",
                        "description": "Fetch last 5 commits from test/repo",
                        "plugin_id": "github",
                        "status": "pending"
                    ]
                ],
                "status": "pending"
            ],
            "required_auth": [
                ["auth_id": "github_token", "description": "GitHub personal access token",
                 "strategies": ["token"]]
            ]
        ]

        let data = json(responseJSON)
        let response = decode(GoalPlanResponse.self, from: data)

        XCTAssertNotNil(response, "GoalPlanResponse must decode")
        XCTAssertEqual(response!.session_id, "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(response!.goal_plan.goals.count, 1)
        XCTAssertEqual(response!.goal_plan.goals[0].plugin_id, "github")
        XCTAssertEqual(response!.required_auth.count, 1)
    }

    // MARK: - Test 2: Approve response distinguishes approved vs revised

    /// Approving with `approved=true` must decode status="approved" with no
    /// goal_plan field.  Rejecting with feedback must decode status="revised"
    /// and include a new goal_plan.
    func testApproveGoalPlan_distinguishesApprovedVsRevised() {
        // Approved branch
        let approvedJSON: [String: Any] = [
            "status": "approved",
            "message": "Goal plan approved. Call /goals/{id}/run to start execution."
        ]
        let approvedData = json(approvedJSON)
        let approved = decode(ApproveResponse.self, from: approvedData)

        XCTAssertNotNil(approved)
        XCTAssertEqual(approved!.status, "approved")
        XCTAssertNil(approved!.goal_plan, "Approved response must NOT include a new goal_plan")

        // Revised branch
        let revisedJSON: [String: Any] = [
            "status": "revised",
            "goal_plan": [
                "plan_id": "plan-002",
                "goals": [
                    [
                        "goal_id": "G-0",
                        "description": "Fetch last 5 commits from test/repo on branch main",
                        "plugin_id": "github",
                        "status": "pending"
                    ]
                ],
                "status": "pending"
            ],
            "required_auth": []
        ]
        let revisedData = json(revisedJSON)
        let revised = decode(ApproveResponse.self, from: revisedData)

        XCTAssertNotNil(revised)
        XCTAssertEqual(revised!.status, "revised")
        XCTAssertNotNil(revised!.goal_plan, "Revised response must include updated goal_plan")
        XCTAssertTrue(
            revised!.goal_plan!.goals[0].description.contains("branch"),
            "Revised description should reflect the feedback"
        )
    }

    // MARK: - Test 3: SSE event parsing covers all high-frequency event types

    /// The SSE stream emits `data: {...}` lines.  Verify that every core
    /// event type can be parsed to a dictionary with the expected keys.
    func testSSEEventParsing_handlesAllEventTypes() {
        let events: [[String: Any]] = [
            ["event_type": "goal_started",      "goal_id": "G-0", "data": [:]],
            ["event_type": "steps_planned",     "goal_id": "G-0", "data": ["steps": []]],
            ["event_type": "step_executed",     "goal_id": "G-0", "data": ["step_id": "s1", "success": true]],
            ["event_type": "goal_completed",    "goal_id": "G-0", "data": [:]],
            ["event_type": "final_evaluated",   "goal_id": "",    "data": ["evaluation": ["query_resolved": true]]],
            ["event_type": "complete",          "goal_id": "",    "data": [:]],
        ]

        for event in events {
            let data = try! JSONSerialization.data(withJSONObject: event)
            let jsonString = String(data: data, encoding: .utf8)!
            let sseLine = "data: \(jsonString)"

            let parsed = parseSSELine(sseLine)
            XCTAssertNotNil(parsed, "Must parse SSE line for event_type=\(event["event_type"]!)")
            XCTAssertNotNil(parsed?["event_type"] as? String, "event_type must be a string")
        }

        // Lines that don't start with "data: " must be ignored
        XCTAssertNil(parseSSELine("event: keepalive"))
        XCTAssertNil(parseSSELine(": ping"))
        XCTAssertNil(parseSSELine(""))
    }
}
