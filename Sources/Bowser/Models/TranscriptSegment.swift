// TranscriptSegment.swift - Model for a single transcribed audio chunk

import Foundation

// =============================================================================
// MARK: - Transcript Segment
// =============================================================================

/// A single transcribed chunk from a meeting recording.
/// Each segment corresponds to one 5-second audio chunk sent to Whisper.
struct TranscriptSegment: Identifiable, Codable, Sendable {
    let id: UUID
    let text: String
    /// Optional speaker label: "You" for mic input, nil for system audio (remote participants)
    let speakerLabel: String?
    let timestamp: Date

    init(
        id: UUID = UUID(),
        text: String,
        speakerLabel: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.speakerLabel = speakerLabel
        self.timestamp = timestamp
    }
}
