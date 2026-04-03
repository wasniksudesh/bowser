// MeetingRecorderService.swift - Core meeting recording and transcription service
// Captures OS-level system audio (SystemAudioCaptureService) and microphone input
// (MicCaptureService) in 5-second chunks, sends to Sidecar Whisper API, maintains
// a live transcript with speaker labels, saves a note with MeetingMetadata, and
// triggers an AI summary via /api/ai/meeting-summary.

import AppKit
import AVFoundation
import Foundation

// =============================================================================
// MARK: - Meeting Recorder Service
// =============================================================================

/// Orchestrates meeting recording: system audio capture → WAV encoding →
/// Sidecar transcription → live transcript + live notes → AI summary → Note.
@Observable
@MainActor
final class MeetingRecorderService {

    // MARK: - Singleton

    static let shared = MeetingRecorderService()

    // MARK: - Public State

    var isRecording: Bool = false
    var isPaused: Bool = false
    var transcriptSegments: [TranscriptSegment] = []
    var meetingNotes: String = ""           // User's live memos during recording
    var elapsedSeconds: Int = 0
    var meetingTitle: String = ""
    var activeTemplate: NoteTemplate? = nil
    var aiSummaryStatus: AISummaryStatus = .pending
    /// Set after stopRecording() so NoteEditorView can observe it
    var lastSavedNoteId: UUID? = nil
    /// RMS audio level 0–1; updated on every incoming PCM packet for waveform display
    var audioLevel: Float = 0.0

    // MARK: - Private State

    private weak var browserState: BrowserState?

    // System audio output (ScreenCaptureKit — 48 kHz stereo)
    private var sampleBuffer: [Float] = []
    private let streamChannels: Int = 2
    private let streamSampleRate: Int = 48000

    // Microphone input (AVCaptureSession — native sample rate mono)
    private var micBuffer: [Float] = []
    private let micChannels: Int = 1
    private var micSampleRate: Int = 48_000

    // First-call sentinels for ⑦ logs
    private var didLogFirstSystemSample = false
    private var didLogFirstMicSample = false

    private var chunkTimer: Timer?
    private var elapsedTimer: Timer?
    private var inFlightTasks: [Task<Void, Never>] = []
    private var recordingStartedAt: Date = Date()
    private let sidecarURL = URL(string: "http://localhost:8765")!
    private var isStopping: Bool = false

    // MARK: - Init

    private init() {}

    func attach(to browserState: BrowserState) {
        self.browserState = browserState
    }

    // MARK: - Recording Lifecycle

    /// Start recording system audio from the OS audio output mix.
    /// Works with any app — browser, WhatsApp, Zoom, FaceTime, etc.
    /// Call `startRecording(template:)` to attach a note template.
    func startRecording(template: NoteTemplate? = nil) {
        NSLog("[RecordStart] ② startRecording() entered — isRecording=%d template='%@'", isRecording ? 1 : 0, template?.title ?? "none")
        guard !isRecording else {
            NSLog("[RecordStart] ② already recording, early return")
            return
        }

        NSLog("[RecordStart] ② resetting state buffers")
        transcriptSegments = []
        meetingNotes = ""
        sampleBuffer = []
        micBuffer = []
        elapsedSeconds = 0
        didLogFirstSystemSample = false
        didLogFirstMicSample = false

        NSLog("[RecordStart] ② setting isRecording = true")
        isRecording = true
        NSLog("[RecordStart] ② isRecording = true — SwiftUI notified")

        isPaused = false
        aiSummaryStatus = .pending
        lastSavedNoteId = nil
        activeTemplate = template
        meetingTitle = ""
        recordingStartedAt = Date()

        // Start mic first so AVAudioEngine's Core Audio graph reconfiguration
        // settles before SCKit begins streaming. Starting SCKit while the graph
        // is being reconfigured crashes CEF's Bowser Helper audio renderer.
        NSLog("[RecordStart] ② launching serial capture startup (mic first, then SCKit)")
        Task {
            await MicCaptureService.shared.start()
            NSLog("[RecordStart] ② MicCapture done — now starting SystemAudio")
            await SystemAudioCaptureService.shared.start()
            NSLog("[RecordStart] ② both capture services started")
        }

        NSLog("[RecordStart] ② scheduling chunkTimer")
        chunkTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.flushAudioChunk() }
        }
        NSLog("[RecordStart] ② scheduling elapsedTimer")
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.elapsedSeconds += 1 }
        }

        NSLog("[RecordStart] ② startRecording COMPLETE — isRecording=%d", isRecording ? 1 : 0)
    }

    /// Pause/resume recording. Audio callbacks continue but samples are discarded.
    func togglePause() {
        guard isRecording else { return }
        isPaused.toggle()
        if isPaused {
            chunkTimer?.invalidate(); chunkTimer = nil
            elapsedTimer?.invalidate(); elapsedTimer = nil
        } else {
            chunkTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.flushAudioChunk() }
            }
            elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.elapsedSeconds += 1 }
            }
        }
    }

    /// Stop recording, flush remaining audio, save note, trigger AI summary.
    func stopRecording() {
        guard isRecording, !isStopping else { return }
        isStopping = true
        let duration = elapsedSeconds
        teardownCaptureSync()

        Task {
            // Await SCKit stop before reading the buffers — otherwise late-arriving
            // samples dispatched from the SCStream callback thread can race the flush.
            await SystemAudioCaptureService.shared.stop()
            await awaitInFlightTasks()
            // Flush any remaining system audio
            if !sampleBuffer.isEmpty {
                await transcribeBuffer(sampleBuffer, channels: streamChannels, sampleRate: streamSampleRate, speakerLabel: nil)
            }
            sampleBuffer = []
            // Flush any remaining mic audio
            if !micBuffer.isEmpty {
                await transcribeBuffer(micBuffer, channels: micChannels, sampleRate: micSampleRate, speakerLabel: "You")
            }
            micBuffer = []
            await saveAsNote(durationSeconds: duration)
            isStopping = false
        }
    }

    /// Stop recording and discard transcript without saving.
    func discardRecording() {
        guard isRecording else { return }
        teardownCaptureSync()
        Task { await SystemAudioCaptureService.shared.stop() }
        transcriptSegments = []
        meetingNotes = ""
        sampleBuffer = []
        micBuffer = []
        inFlightTasks.forEach { $0.cancel() }
        inFlightTasks = []
        activeTemplate = nil
        isStopping = false
        print("[MeetingRecorder] Recording discarded")
    }

    // MARK: - Audio Data Ingestion

    /// Called by SystemAudioCaptureService with OS output audio (48 kHz stereo).
    func receiveAudioData(_ samples: [Float]) {
        guard isRecording, !isPaused else { return }
        if !didLogFirstSystemSample {
            didLogFirstSystemSample = true
            NSLog("[RecordStart] ⑦ first system audio sample — count=%d", samples.count)
        }
        sampleBuffer.append(contentsOf: samples)

        // Compute RMS for waveform display; scale ×5 so typical speech fills the bars.
        // Use max() so a lower system audio level doesn't overwrite a higher mic level
        // when both callbacks fire in the same run-loop turn.
        let sumSq = samples.reduce(0.0 as Float) { $0 + $1 * $1 }
        let rms = samples.isEmpty ? 0 : sqrt(sumSq / Float(samples.count))
        audioLevel = max(audioLevel, min(1.0, rms * 5.0))
    }

    /// Called by MicCaptureService with microphone input (native sample rate, mono).
    func receiveMicData(_ samples: [Float], sampleRate: Int) {
        guard isRecording, !isPaused else { return }
        if !didLogFirstMicSample {
            didLogFirstMicSample = true
            NSLog("[RecordStart] ⑦ first mic sample — count=%d sampleRate=%d", samples.count, sampleRate)
        }
        micSampleRate = sampleRate
        micBuffer.append(contentsOf: samples)

        let sumSq = samples.reduce(0.0 as Float) { $0 + $1 * $1 }
        let rms = samples.isEmpty ? 0 : sqrt(sumSq / Float(samples.count))
        audioLevel = max(audioLevel, min(1.0, rms * 5.0))
    }

    // MARK: - Private Teardown

    /// Synchronously stops timers, clears recording flags, and stops mic capture.
    /// Callers must separately `await SystemAudioCaptureService.shared.stop()` to ensure
    /// no further SCKit samples arrive before the final buffer flush.
    private func teardownCaptureSync() {
        NSLog("[RecordStart] ⑦ teardownCaptureSync — isRecording=%d", isRecording ? 1 : 0)
        chunkTimer?.invalidate(); chunkTimer = nil
        elapsedTimer?.invalidate(); elapsedTimer = nil
        isRecording = false
        isPaused = false
        audioLevel = 0.0
        MicCaptureService.shared.stop()
        NSLog("[RecordStart] ⑦ teardownCaptureSync complete")
    }

    // MARK: - Audio Chunking

    private func flushAudioChunk() {
        // Flush system audio (OS output — remote participants)
        if !sampleBuffer.isEmpty {
            let chunk = sampleBuffer
            sampleBuffer = []
            print("[MeetingRecorder] flush system audio — \(chunk.count) samples (\(streamChannels)ch @ \(streamSampleRate)Hz)")
            let task = Task {
                await transcribeBuffer(chunk, channels: streamChannels, sampleRate: streamSampleRate, speakerLabel: nil)
            }
            inFlightTasks.append(task)
        }

        // Flush mic audio (local input — the user)
        if !micBuffer.isEmpty {
            let chunk = micBuffer
            micBuffer = []
            print("[MeetingRecorder] flush mic audio — \(chunk.count) samples (\(micChannels)ch @ \(micSampleRate)Hz)")
            let task = Task {
                await transcribeBuffer(chunk, channels: self.micChannels, sampleRate: self.micSampleRate, speakerLabel: "You")
            }
            inFlightTasks.append(task)
        }
    }

    private func awaitInFlightTasks() async {
        let tasks = inFlightTasks
        inFlightTasks = []
        for task in tasks { await task.value }
    }

    // MARK: - Transcription

    private func transcribeBuffer(_ samples: [Float], channels: Int, sampleRate: Int, speakerLabel: String?) async {
        guard let wavData = encodeWAV(samples: samples, channels: channels, sampleRate: sampleRate) else {
            print("[MeetingRecorder] Failed to encode WAV for chunk")
            return
        }
        do {
            let text = try await sendToSidecar(wavData: wavData)
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            let source = speakerLabel ?? "remote"
            let segment = TranscriptSegment(text: text, speakerLabel: speakerLabel)
            transcriptSegments.append(segment)
            print("[MeetingRecorder] Transcribed [\(source)]: \(text.prefix(60))…")
        } catch {
            print("[MeetingRecorder] Transcription error: \(error)")
        }
    }

    private func sendToSidecar(wavData: Data) async throws -> String {
        let url = sidecarURL.appendingPathComponent("api/transcribe")
        let boundary = "BowserAudioBoundary\(UUID().uuidString.prefix(8))"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"chunk.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct R: Decodable { let text: String }
        return try JSONDecoder().decode(R.self, from: data).text
    }

    // MARK: - WAV Encoding

    private func encodeWAV(samples: [Float], channels: Int, sampleRate: Int) -> Data? {
        guard channels > 0, sampleRate > 0, !samples.isEmpty else { return nil }
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = UInt16(channels) * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count) * UInt32(bitsPerSample / 8)
        var wav = Data()
        wav.append(contentsOf: "RIFF".utf8)
        wav.appendLEUInt32(36 + dataSize)
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.appendLEUInt32(16)
        wav.appendLEUInt16(1)
        wav.appendLEUInt16(UInt16(channels))
        wav.appendLEUInt32(UInt32(sampleRate))
        wav.appendLEUInt32(byteRate)
        wav.appendLEUInt16(blockAlign)
        wav.appendLEUInt16(bitsPerSample)
        wav.append(contentsOf: "data".utf8)
        wav.appendLEUInt32(dataSize)
        for sample in samples {
            let s16 = Int16(max(-32768, min(32767, Int(max(-1, min(1, sample)) * 32767))))
            wav.appendLEInt16(s16)
        }
        return wav
    }

    // MARK: - Save as Note

    @MainActor
    func saveAsNote(durationSeconds: Int = 0) async {
        guard !transcriptSegments.isEmpty || !meetingNotes.isEmpty else {
            print("[MeetingRecorder] Nothing to save — no transcript or notes")
            return
        }
        guard let browserState = browserState,
              let folderId = browserState.currentFolderId else {
            print("[MeetingRecorder] No folder to save note into")
            return
        }

        let rawTranscript = transcriptSegments.map { $0.text }.joined(separator: "\n")
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        let displayTitle = meetingTitle.isEmpty ? "Meeting" : meetingTitle
        let title = "Meeting – \(displayTitle) – \(dateStr)"

        let metadata = MeetingMetadata(
            rawTranscript: rawTranscript,
            userNotes: meetingNotes,
            templateId: activeTemplate?.id,
            durationSeconds: durationSeconds,
            recordedAt: recordingStartedAt,
            aiSummaryStatus: .pending
        )

        let initialRTFD = buildRawRTFDContent()

        var note = Note(
            title: title,
            contentRTFD: initialRTFD,
            meetingMetadata: metadata
        )
        NotePersistence.shared.saveNote(note, forFolder: folderId)
        lastSavedNoteId = note.id
        browserState.openNoteTab(noteId: note.id, title: title)
        print("[MeetingRecorder] Saved meeting note: \(title)")

        aiSummaryStatus = .generating
        await requestAISummary(noteId: note.id, folderId: folderId, metadata: metadata, note: &note)
    }

    // MARK: - AI Summary

    private func requestAISummary(
        noteId: UUID,
        folderId: UUID,
        metadata: MeetingMetadata,
        note: inout Note
    ) async {
        guard !metadata.rawTranscript.isEmpty else {
            aiSummaryStatus = .failed
            return
        }

        let sections = activeTemplate?.sections.map { ["title": $0.title, "description": $0.description] } ?? []
        let payload: [String: Any] = [
            "transcript": metadata.rawTranscript,
            "notes": metadata.userNotes,
            "template_sections": sections,
            "meeting_title": meetingTitle,
        ]

        do {
            guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
                throw URLError(.cannotParseResponse)
            }
            let url = sidecarURL.appendingPathComponent("api/ai/meeting-summary")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            struct SummaryResponse: Decodable { let summary: String }
            let result = try JSONDecoder().decode(SummaryResponse.self, from: data)
            let summaryText = result.summary

            let rtfd = markdownToRTFD(summaryText)

            var updatedMeta = metadata
            updatedMeta.aiSummaryStatus = .done
            note.contentRTFD = rtfd
            note.meetingMetadata = updatedMeta
            note.updatedAt = Date()
            NotePersistence.shared.saveNote(note, forFolder: folderId)

            aiSummaryStatus = .done
            print("[MeetingRecorder] AI summary written to note: \(noteId)")
        } catch {
            print("[MeetingRecorder] AI summary failed: \(error)")
            if var reloaded = NotePersistence.shared.loadNote(id: noteId, forFolder: folderId) {
                reloaded.meetingMetadata?.aiSummaryStatus = .failed
                NotePersistence.shared.saveNote(reloaded, forFolder: folderId)
            }
            aiSummaryStatus = .failed
        }
    }

    // MARK: - Re-summarize (called from NoteEditorView)

    /// Re-trigger AI summary for an existing meeting note, optionally with a new template.
    func resummmarize(noteId: UUID, folderId: UUID, template: NoteTemplate? = nil) async {
        guard let note = NotePersistence.shared.loadNote(id: noteId, forFolder: folderId),
              var meta = note.meetingMetadata else { return }
        let usedTemplate = template ?? NoteTemplate.builtIn.first(where: { $0.id == meta.templateId })
        activeTemplate = usedTemplate
        meta.aiSummaryStatus = .generating
        var mutableNote = note
        mutableNote.meetingMetadata = meta
        NotePersistence.shared.saveNote(mutableNote, forFolder: folderId)
        aiSummaryStatus = .generating
        await requestAISummary(noteId: noteId, folderId: folderId, metadata: meta, note: &mutableNote)
    }

    // MARK: - RTFD Builders

    private func buildRawRTFDContent() -> Data {
        let attrString = NSMutableAttributedString()
        for segment in transcriptSegments {
            let timeStr = DateFormatter.localizedString(
                from: segment.timestamp, dateStyle: .none, timeStyle: .medium
            )
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
            attrString.append(NSAttributedString(string: "\(timeStr)\n", attributes: headerAttrs))
            if let speaker = segment.speakerLabel {
                attrString.append(NSAttributedString(
                    string: "\(speaker): ",
                    attributes: [.font: NSFont.boldSystemFont(ofSize: 13)]
                ))
            }
            attrString.append(NSAttributedString(
                string: segment.text + "\n\n",
                attributes: [.font: NSFont.systemFont(ofSize: 13)]
            ))
        }
        return (try? attrString.data(
            from: NSRange(location: 0, length: attrString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )) ?? Data()
    }

    private func markdownToRTFD(_ markdown: String) -> Data {
        if let swiftAttr = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            let mutable = NSMutableAttributedString(swiftAttr)
            mutable.addAttribute(
                .font,
                value: NSFont.systemFont(ofSize: 13),
                range: NSRange(location: 0, length: mutable.length)
            )
            let docAttrs: [NSAttributedString.DocumentAttributeKey: Any] = [
                .documentType: NSAttributedString.DocumentType.rtfd
            ]
            return (try? mutable.data(
                from: NSRange(location: 0, length: mutable.length),
                documentAttributes: docAttrs
            )) ?? Data()
        }
        let plain = NSAttributedString(
            string: markdown,
            attributes: [.font: NSFont.systemFont(ofSize: 13) as Any]
        )
        let docAttrs: [NSAttributedString.DocumentAttributeKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtfd
        ]
        return (try? plain.data(
            from: NSRange(location: 0, length: plain.length),
            documentAttributes: docAttrs
        )) ?? Data()
    }
}

// =============================================================================
// MARK: - Data Helpers
// =============================================================================

private extension Data {
    mutating func appendLEUInt16(_ v: UInt16) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
    mutating func appendLEUInt32(_ v: UInt32) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
    mutating func appendLEInt16(_ v: Int16) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
