// NoteEditorView.swift - Full note editing view with title, toolbar, and rich text editor
// Extended with template picker, AI summary status banner, and meeting metadata footer.

import AppKit
import SwiftUI

// =============================================================================
// MARK: - Note Editor View
// =============================================================================

/// Main content area view displayed when a note tab is active.
/// When the note has `meetingMetadata`, additional meeting-specific UI is shown:
///   - AI summary status banner (generating / done / failed)
///   - Re-summarize button
///   - Collapsible raw transcript section
///   - Meeting metadata footer (duration, recorded at, template used)
struct NoteEditorView: View {

    let noteId: UUID
    @Bindable var browserState: BrowserState

    @State private var title: String = ""
    @State private var rtfdData: Data = Data()
    @State private var isLoaded = false
    @State private var saveTask: Task<Void, Never>?
    @State private var editorCoordinator: RichTextEditor.Coordinator?
    @State private var showLinkSheet = false
    @State private var linkURLText = ""

    // Meeting-specific state
    @State private var meetingMetadata: MeetingMetadata? = nil
    @State private var showTemplatePicker = false
    @State private var showRawTranscript = false
    @State private var showResummarizeMenu = false

    var body: some View {
        VStack(spacing: 0) {
            // AI summary status banner (only for meeting notes while generating)
            if let meta = meetingMetadata {
                aiSummaryBanner(meta: meta)
            }
            titleSection
            Divider().opacity(0.5)
            formattingToolbar
            Divider().opacity(0.5)
            editorSection

            // Collapsible raw transcript
            if let meta = meetingMetadata, !meta.rawTranscript.isEmpty {
                rawTranscriptSection(meta: meta)
            }
            // Meeting metadata footer
            if let meta = meetingMetadata {
                meetingMetadataFooter(meta: meta)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .task { loadNote() }
        .onDisappear {
            saveTask?.cancel()
            persistNote()
        }
        .sheet(isPresented: $showLinkSheet) { linkSheet }
        .sheet(isPresented: $showTemplatePicker) {
            TemplatePickerView(
                onSelect: { template in
                    applyTemplate(template)
                },
                onSkip: { }
            )
        }
        // Observe AI summary status from the recorder service
        .onChange(of: browserState.meetingRecorderService.aiSummaryStatus) { _, status in
            guard browserState.meetingRecorderService.lastSavedNoteId == noteId else { return }
            if status == .done || status == .failed {
                reloadNote()
            }
        }
    }

    // MARK: - AI Summary Banner

    @ViewBuilder
    private func aiSummaryBanner(meta: MeetingMetadata) -> some View {
        switch meta.aiSummaryStatus {
        case .generating:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
                Text("Generating AI summary…")
                    .font(.system(size: 12))
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.08))

        case .done:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 13))
                Text("AI summary ready")
                    .font(.system(size: 12))
                Spacer()
                Button("Re-summarize") {
                    Task {
                        guard let folderId = browserState.currentFolderId else { return }
                        await browserState.meetingRecorderService.resummmarize(
                            noteId: noteId, folderId: folderId
                        )
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.07))

        case .failed:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 13))
                Text("AI summary failed — raw transcript saved.")
                    .font(.system(size: 12))
                Spacer()
                Button("Retry") {
                    Task {
                        guard let folderId = browserState.currentFolderId else { return }
                        await browserState.meetingRecorderService.resummmarize(
                            noteId: noteId, folderId: folderId
                        )
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.08))

        case .pending:
            EmptyView()
        }
    }

    // MARK: - Title Section

    private var titleSection: some View {
        TextField("Untitled Note", text: $title)
            .textFieldStyle(.plain)
            .font(.system(size: 28, weight: .bold))
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 12)
            .onChange(of: title) { _, newValue in
                updateTabTitle(newValue)
                scheduleSave()
            }
    }

    // MARK: - Formatting Toolbar

    private var formattingToolbar: some View {
        HStack(spacing: 2) {
            toolbarButton(icon: "bold", tooltip: "Bold") {
                editorCoordinator?.toggleBold()
            }
            toolbarButton(icon: "italic", tooltip: "Italic") {
                editorCoordinator?.toggleItalic()
            }
            toolbarButton(icon: "underline", tooltip: "Underline") {
                editorCoordinator?.toggleUnderline()
            }

            Divider().frame(height: 18).padding(.horizontal, 4)

            toolbarButton(icon: "textformat.size.larger", tooltip: "Heading 1") {
                editorCoordinator?.applyHeading(1)
            }
            toolbarButton(icon: "textformat.size", tooltip: "Heading 2") {
                editorCoordinator?.applyHeading(2)
            }
            toolbarButton(icon: "textformat", tooltip: "Heading 3") {
                editorCoordinator?.applyHeading(3)
            }

            Divider().frame(height: 18).padding(.horizontal, 4)

            toolbarButton(icon: "list.bullet", tooltip: "Bullet List") {
                editorCoordinator?.toggleBulletList()
            }
            toolbarButton(icon: "link", tooltip: "Insert Link") {
                linkURLText = ""
                showLinkSheet = true
            }

            Divider().frame(height: 18).padding(.horizontal, 4)

            // Template picker — shown when note body is empty or always for discoverability
            toolbarButton(icon: "square.grid.2x2", tooltip: "Use Template") {
                showTemplatePicker = true
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func toolbarButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.04))
        )
        .help(tooltip)
    }

    // MARK: - Editor Section

    private var editorSection: some View {
        RichTextEditor(rtfdData: $rtfdData) {
            scheduleSave()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                captureCoordinator()
            }
        }
    }

    // MARK: - Raw Transcript Section

    private func rawTranscriptSection(meta: MeetingMetadata) -> some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showRawTranscript.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showRawTranscript ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Image(systemName: "text.quote")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text("Raw Transcript")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(meta.rawTranscript.split(separator: " ").count) words")
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showRawTranscript {
                ScrollView {
                    Text(meta.rawTranscript)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                }
                .frame(maxHeight: 200)
                .background(Color.primary.opacity(0.02))
            }
        }
    }

    // MARK: - Meeting Metadata Footer

    private func meetingMetadataFooter(meta: MeetingMetadata) -> some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            HStack(spacing: 16) {
                Label(meta.formattedDuration, systemImage: "clock")
                Label(
                    DateFormatter.localizedString(
                        from: meta.recordedAt, dateStyle: .short, timeStyle: .short
                    ),
                    systemImage: "calendar"
                )
                if let templateId = meta.templateId,
                   let template = NoteTemplate.builtIn.first(where: { $0.id == templateId }) {
                    Label(template.title, systemImage: "square.grid.2x2")
                }
                Spacer()
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Link Sheet

    private var linkSheet: some View {
        VStack(spacing: 16) {
            Text("Insert Link")
                .font(.headline)
            TextField("https://example.com", text: $linkURLText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            HStack {
                Button("Cancel") { showLinkSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Insert") {
                    if let url = URL(string: linkURLText), !linkURLText.isEmpty {
                        editorCoordinator?.insertLink(url: url)
                    }
                    showLinkSheet = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    // MARK: - Template Application

    private func applyTemplate(_ template: NoteTemplate) {
        guard let folderId = browserState.currentFolderId else { return }
        // Convert starterMarkdown to RTFD
        let attrStr = NSAttributedString(
            string: template.starterMarkdown,
            attributes: [.font: NSFont.systemFont(ofSize: 13)]
        )
        let rtfd = (try? attrStr.data(
            from: NSRange(location: 0, length: attrStr.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        )) ?? Data()
        rtfdData = rtfd
        if title.isEmpty || title == "Untitled Note" {
            title = template.title
            updateTabTitle(title)
        }
        var note = NotePersistence.shared.loadNote(id: noteId, forFolder: folderId) ?? Note(id: noteId)
        note.title = title
        note.contentRTFD = rtfd
        note.updatedAt = Date()
        NotePersistence.shared.saveNote(note, forFolder: folderId)
    }

    // MARK: - Persistence

    private func loadNote() {
        guard !isLoaded, let folderId = browserState.currentFolderId else { return }
        if let note = NotePersistence.shared.loadNote(id: noteId, forFolder: folderId) {
            title = note.title
            rtfdData = note.contentRTFD
            meetingMetadata = note.meetingMetadata
        }
        isLoaded = true
    }

    private func reloadNote() {
        guard let folderId = browserState.currentFolderId else { return }
        if let note = NotePersistence.shared.loadNote(id: noteId, forFolder: folderId) {
            rtfdData = note.contentRTFD
            meetingMetadata = note.meetingMetadata
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            persistNote()
        }
    }

    private func persistNote() {
        guard let folderId = browserState.currentFolderId else { return }
        var note = NotePersistence.shared.loadNote(id: noteId, forFolder: folderId) ?? Note(id: noteId)
        note.title = title.isEmpty ? "Untitled Note" : title
        note.contentRTFD = rtfdData
        note.updatedAt = Date()
        NotePersistence.shared.saveNote(note, forFolder: folderId)
    }

    private func updateTabTitle(_ newTitle: String) {
        let displayTitle = newTitle.isEmpty ? "Untitled Note" : newTitle
        if let tabId = browserState.activeTab?.id {
            browserState.tabManager.updateTab(id: tabId, title: displayTitle)
        }
    }

    private func captureCoordinator() {
        guard let window = NSApp.keyWindow else { return }
        for textView in allTextViews(in: window.contentView) {
            if let coordinator = textView.delegate as? RichTextEditor.Coordinator {
                editorCoordinator = coordinator
                return
            }
        }
    }

    private func allTextViews(in view: NSView?) -> [NSTextView] {
        guard let view else { return [] }
        var result: [NSTextView] = []
        if let tv = view as? NSTextView { result.append(tv) }
        for sub in view.subviews { result.append(contentsOf: allTextViews(in: sub)) }
        return result
    }
}
