// MeetingMetadata.swift - Preserved meeting context attached to a Note
// Stores the raw transcript, user memos, template reference, and AI summary
// status so the note can be re-summarized at any time.

import Foundation

// =============================================================================
// MARK: - AI Summary Status
// =============================================================================

enum AISummaryStatus: String, Codable, Sendable {
    case pending    // Recording stopped; summary not yet requested
    case generating // HTTP request in flight
    case done       // Summary written to note body
    case failed     // Network / API error
}

// =============================================================================
// MARK: - Meeting Metadata
// =============================================================================

/// Attached to a Note when it was created from a meeting recording.
/// Preserves the raw data so the user can re-summarize with a different
/// template or inspect the original transcript.
struct MeetingMetadata: Codable, Sendable {
    /// Full concatenated transcript text from all `TranscriptSegment` objects.
    let rawTranscript: String
    /// User's live memos typed during the recording.
    let userNotes: String
    /// ID of the `NoteTemplate` that was active when recording started, if any.
    let templateId: String?
    /// Total recording duration in seconds.
    let durationSeconds: Int
    /// Wall-clock time when recording started.
    let recordedAt: Date
    /// Current state of the AI summarization pipeline.
    var aiSummaryStatus: AISummaryStatus

    init(
        rawTranscript: String,
        userNotes: String,
        templateId: String? = nil,
        durationSeconds: Int,
        recordedAt: Date = Date(),
        aiSummaryStatus: AISummaryStatus = .pending
    ) {
        self.rawTranscript = rawTranscript
        self.userNotes = userNotes
        self.templateId = templateId
        self.durationSeconds = durationSeconds
        self.recordedAt = recordedAt
        self.aiSummaryStatus = aiSummaryStatus
    }

    /// Human-readable duration string, e.g. "23 min 45 sec".
    var formattedDuration: String {
        let h = durationSeconds / 3600
        let m = (durationSeconds % 3600) / 60
        let s = durationSeconds % 60
        if h > 0 { return "\(h) hr \(m) min" }
        if m > 0 { return "\(m) min \(s) sec" }
        return "\(s) sec"
    }
}
