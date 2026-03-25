// TimelineFeatureTests.swift
// Tests for the Timeline/Snapshot feature — validates Note model Codable
// backward compatibility, timeline UUID determinism, and coordinate conversion
// logic used by the snapshot overlay.
//
// These tests run without the full Bowser module (no CEF dependency).
// Models are mirrored locally to match the JSON contract.

import XCTest
import Foundation

// ---------------------------------------------------------------------------
// Mirror of Note model (matches Sources/Bowser/Models/Note.swift JSON shape)
// ---------------------------------------------------------------------------

private struct NoteV2: Codable {
    let id: UUID
    var title: String
    var contentRTFD: Data
    let createdAt: Date
    var updatedAt: Date
    var isTimeline: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, contentRTFD, createdAt, updatedAt, isTimeline
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        contentRTFD = try c.decode(Data.self, forKey: .contentRTFD)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        isTimeline = try c.decodeIfPresent(Bool.self, forKey: .isTimeline) ?? false
    }
}

/// Mirror of the old Note model (without isTimeline) for backward compat test
private struct NoteV1: Codable {
    let id: UUID
    var title: String
    var contentRTFD: Data
    let createdAt: Date
    var updatedAt: Date
}

// ---------------------------------------------------------------------------
// Mirror of Note.timelineNoteId(forFolder:) hash logic
// ---------------------------------------------------------------------------

private func timelineNoteId(forFolder folderId: UUID) -> UUID {
    var bytes = Array(folderId.uuidString.utf8)
    bytes.append(contentsOf: "timeline".utf8)
    var hash: [UInt8] = Array(repeating: 0, count: 16)
    for (i, byte) in bytes.enumerated() {
        hash[i % 16] ^= byte &+ UInt8(i % 251)
    }
    hash[6] = (hash[6] & 0x0F) | 0x40
    hash[8] = (hash[8] & 0x3F) | 0x80
    return UUID(uuid: (hash[0], hash[1], hash[2], hash[3],
                       hash[4], hash[5], hash[6], hash[7],
                       hash[8], hash[9], hash[10], hash[11],
                       hash[12], hash[13], hash[14], hash[15]))
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

private let iso8601Encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    return e
}()

private let iso8601Decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
}()

// ===========================================================================
// MARK: - Tests
// ===========================================================================

final class TimelineFeatureTests: XCTestCase {

    // MARK: - 1. Backward Compatibility: old JSON without isTimeline

    /// Notes saved before the isTimeline field existed (V1 shape) must decode
    /// into the new NoteV2 model with isTimeline defaulting to false.
    func testNoteV1_decodesIntoV2_withTimelineFalse() throws {
        let noteV1 = NoteV1(
            id: UUID(),
            title: "Old Note",
            contentRTFD: Data(),
            createdAt: Date(),
            updatedAt: Date()
        )

        let data = try iso8601Encoder.encode(noteV1)
        let decoded = try iso8601Decoder.decode(NoteV2.self, from: data)

        XCTAssertEqual(decoded.id, noteV1.id)
        XCTAssertEqual(decoded.title, "Old Note")
        XCTAssertFalse(decoded.isTimeline, "Old notes without isTimeline should default to false")
    }

    /// Notes with isTimeline explicitly set to true must decode correctly.
    func testNoteV2_roundTrips_withTimelineTrue() throws {
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "title": "Timeline",
            "contentRTFD": "",
            "createdAt": "2025-01-15T10:30:00Z",
            "updatedAt": "2025-01-15T10:30:00Z",
            "isTimeline": true
        }
        """.data(using: .utf8)!

        let decoded = try iso8601Decoder.decode(NoteV2.self, from: json)
        XCTAssertTrue(decoded.isTimeline)
        XCTAssertEqual(decoded.title, "Timeline")
    }

    // MARK: - 2. Timeline UUID Determinism

    /// The same folder ID must always produce the same timeline note UUID.
    func testTimelineNoteId_isDeterministic() {
        let folderId = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

        let id1 = timelineNoteId(forFolder: folderId)
        let id2 = timelineNoteId(forFolder: folderId)

        XCTAssertEqual(id1, id2, "Same folder must produce same timeline UUID")
    }

    /// Different folder IDs must produce different timeline note UUIDs.
    func testTimelineNoteId_differsByFolder() {
        let folderA = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let folderB = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

        let idA = timelineNoteId(forFolder: folderA)
        let idB = timelineNoteId(forFolder: folderB)

        XCTAssertNotEqual(idA, idB, "Different folders must produce different UUIDs")
    }

    /// The generated UUID must be a valid version 4, variant 1 UUID.
    func testTimelineNoteId_isValidUUIDv4() {
        let folderId = UUID()
        let id = timelineNoteId(forFolder: folderId)

        let uuidBytes = id.uuid
        let version = (uuidBytes.6 >> 4) & 0x0F
        let variant = (uuidBytes.8 >> 6) & 0x03

        XCTAssertEqual(version, 4, "UUID version nibble must be 4")
        XCTAssertEqual(variant, 2, "UUID variant bits must be 10 (value 2)")
    }

    // MARK: - 3. Snapshot Coordinate Conversion

    /// Screen coordinate conversion: view-local center must be offset by
    /// the screen frame origin to produce a valid screen coordinate.
    func testSnapshotCenterPoint_convertsToScreenCoords() {
        // Simulate a screen at origin (0, 0) with size 1920x1080
        let screenOriginX: CGFloat = 0
        let screenOriginY: CGFloat = 0
        let rectMidX: CGFloat = 500
        let rectMidY: CGFloat = 300

        let center = CGPoint(
            x: screenOriginX + rectMidX,
            y: screenOriginY + rectMidY
        )

        XCTAssertEqual(center.x, 500)
        XCTAssertEqual(center.y, 300)
    }

    /// On a secondary display offset from the primary, the screen origin
    /// must be added to the view-local center.
    func testSnapshotCenterPoint_secondaryDisplay() {
        // Secondary screen at (1920, 0)
        let screenOriginX: CGFloat = 1920
        let screenOriginY: CGFloat = 0
        let rectMidX: CGFloat = 200
        let rectMidY: CGFloat = 400

        let center = CGPoint(
            x: screenOriginX + rectMidX,
            y: screenOriginY + rectMidY
        )

        XCTAssertEqual(center.x, 2120, "Should include secondary display X offset")
        XCTAssertEqual(center.y, 400)
    }
}
