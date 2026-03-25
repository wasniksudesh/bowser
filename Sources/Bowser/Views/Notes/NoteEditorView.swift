// NoteEditorView.swift - Full note editing view with title, toolbar, and rich text editor

import AppKit
import SwiftUI

// =============================================================================
// MARK: - Note Editor View
// =============================================================================

/// Main content area view displayed when a note tab is active.
/// Consists of an editable title, a formatting toolbar, and the rich text editor.
/// All changes are auto-saved with a 0.5s debounce.
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

    var body: some View {
        VStack(spacing: 0) {
            titleSection
            Divider().opacity(0.5)
            formattingToolbar
            Divider().opacity(0.5)
            editorSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .task { loadNote() }
        .onDisappear {
            saveTask?.cancel()
            persistNote()
        }
        .sheet(isPresented: $showLinkSheet) { linkSheet }
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
            // Grab the coordinator reference after first render cycle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                captureCoordinator()
            }
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

    // MARK: - Persistence

    private func loadNote() {
        guard !isLoaded, let folderId = browserState.currentFolderId else { return }
        if let note = NotePersistence.shared.loadNote(id: noteId, forFolder: folderId) {
            title = note.title
            rtfdData = note.contentRTFD
        }
        isLoaded = true
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

    /// Capture the coordinator from the RichTextEditor's NSTextView hierarchy.
    /// We walk the view host to find our NSTextView's delegate.
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
        if let tv = view as? NSTextView {
            result.append(tv)
        }
        for sub in view.subviews {
            result.append(contentsOf: allTextViews(in: sub))
        }
        return result
    }
}
