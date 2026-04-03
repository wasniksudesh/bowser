// RecordingPanelView.swift - Dual-tab recording panel (Notes + Transcript)
// Notes tab: live memo TextEditor bound to recorder.meetingNotes
// Transcript tab: live Whisper segments with auto-scroll

import SwiftUI

// =============================================================================
// MARK: - Panel Tab
// =============================================================================

private enum PanelTab: String, CaseIterable {
    case notes      = "Notes"
    case transcript = "Transcript"

    var icon: String {
        switch self {
        case .notes:      return "pencil"
        case .transcript: return "text.bubble"
        }
    }
}

// =============================================================================
// MARK: - Recording Panel View
// =============================================================================

struct RecordingPanelView: View {

    @Bindable var recorder: MeetingRecorderService

    @State private var selectedTab: PanelTab = .transcript
    @State private var showStopConfirm = false
    @State private var noteTitle: String = ""

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            tabPicker
            Divider()
            tabContent
            Divider()
            controlBar
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.12))
        .alert("Save Meeting Note", isPresented: $showStopConfirm) {
            TextField("Meeting title", text: $noteTitle)
            Button("Save & Stop") {
                recorder.meetingTitle = noteTitle.isEmpty ? recorder.meetingTitle : noteTitle
                recorder.stopRecording()
            }
            Button("Discard", role: .destructive) {
                recorder.discardRecording()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The transcript and your notes will be summarized by AI and saved.")
        }
        .onAppear {
            NSLog("[RecordStart] ④ RecordingPanelView onAppear — isRecording=%d", recorder.isRecording ? 1 : 0)
            noteTitle = recorder.meetingTitle
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 6) {
            WaveformBarsView(
                isAnimating: recorder.isRecording,
                isPaused: recorder.isPaused,
                color: recorder.isPaused ? .orange : .red
            )
            .frame(width: 18, height: 14)

            Text(recorder.isPaused ? "Paused" : "Recording")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(recorder.isPaused ? .secondary : .primary)

            if let template = recorder.activeTemplate {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(template.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(formattedElapsed)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(PanelTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10, weight: .medium))
                        Text(tab.rawValue)
                            .font(.system(size: 11, weight: .medium))
                        if tab == .transcript, !recorder.transcriptSegments.isEmpty {
                            Text("\(recorder.transcriptSegments.count)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red.opacity(0.75), in: Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                    .background(
                        selectedTab == tab
                            ? Color.primary.opacity(0.07)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .notes:
            notesTab
        case .transcript:
            transcriptTab
        }
    }

    // MARK: - Notes Tab

    private var notesTab: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $recorder.meetingNotes)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            if recorder.meetingNotes.isEmpty {
                Text("Jot down key points, decisions, or follow-ups…")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Transcript Tab

    private var transcriptTab: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if recorder.transcriptSegments.isEmpty {
                        emptyTranscriptState
                    } else {
                        ForEach(recorder.transcriptSegments) { segment in
                            SegmentRow(segment: segment)
                                .id(segment.id)
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .onChange(of: recorder.transcriptSegments.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                // Auto-switch to transcript tab when first segment arrives
                if recorder.transcriptSegments.count == 1 {
                    withAnimation { selectedTab = .transcript }
                }
            }
        }
    }

    private var emptyTranscriptState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("Listening for audio…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 8) {
            Button(action: { recorder.togglePause() }) {
                Label(
                    recorder.isPaused ? "Resume" : "Pause",
                    systemImage: recorder.isPaused ? "play.fill" : "pause.fill"
                )
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PanelControlButtonStyle(color: .blue))

            Button(action: {
                noteTitle = recorder.meetingTitle
                showStopConfirm = true
            }) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PanelControlButtonStyle(color: .red))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private var formattedElapsed: String {
        let h = recorder.elapsedSeconds / 3600
        let m = (recorder.elapsedSeconds % 3600) / 60
        let s = recorder.elapsedSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

// =============================================================================
// MARK: - Segment Row
// =============================================================================

private struct SegmentRow: View {
    let segment: TranscriptSegment

    private var speakerColor: Color {
        guard let label = segment.speakerLabel else { return .blue }
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        return palette[abs(label.hashValue) % palette.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let speaker = segment.speakerLabel {
                    Text(speaker)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(speakerColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(speakerColor.opacity(0.12), in: Capsule())
                }
                Text(segment.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Text(segment.text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// =============================================================================
// MARK: - Button Style
// =============================================================================

private struct PanelControlButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(configuration.isPressed ? 0.25 : 0.12))
            )
            .foregroundStyle(color)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
