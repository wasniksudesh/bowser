// SelectionPopupBar.swift - Floating action bar for text selection and snapshots
// Appears near the mouse cursor with Save, Note picker, and Ask AI actions

import SwiftUI

// =============================================================================
// MARK: - Selection Popup Bar
// =============================================================================

/// Floating pill-shaped bar that appears after text selection or snapshot capture.
/// Provides Save (to timeline), Note picker (save to specific note), and Ask AI actions.
struct SelectionPopupBar: View {

    @Bindable var browserState: BrowserState

    var selectedText: String?
    var capturedImage: NSImage?
    var sourceURL: URL?
    var screenPosition: CGPoint?
    var onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        GeometryReader { geo in
            // Transparent backdrop: tapping anywhere outside the bar dismisses it
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            if isVisible, let anchor = anchorPoint(in: geo) {
                popupContent
                    .position(x: anchor.x, y: anchor.y)
                    .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
            }
        }
        .animation(ArcTheme.springAnimation, value: isVisible)
        .onAppear {
            withAnimation(ArcTheme.springAnimation) {
                isVisible = true
            }
        }
    }

    // MARK: - Popup Content

    private var popupContent: some View {
        HStack(spacing: 4) {
            saveButton
            notePickerButton
            Divider().frame(height: 20).opacity(0.4)
            askAIButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThickMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: ArcTheme.primaryShadow.color, radius: ArcTheme.primaryShadow.radius, y: ArcTheme.primaryShadow.y)
        .shadow(color: ArcTheme.secondaryShadow.color, radius: ArcTheme.secondaryShadow.radius, y: ArcTheme.secondaryShadow.y)
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            saveToTimeline()
            dismiss()
        } label: {
            Label("Save", systemImage: "square.and.arrow.down")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(
            Capsule().fill(Color.primary.opacity(0.06))
        )
        .help("Save to Timeline")
    }

    // MARK: - Note Picker

    private var notePickerButton: some View {
        Menu {
            let notes = currentFolderNotes()

            Section {
                Label("Timeline (default)", systemImage: "clock.arrow.circlepath")
            }

            if !notes.filter({ !$0.isTimeline }).isEmpty {
                Divider()

                ForEach(notes.filter({ !$0.isTimeline }), id: \.id) { note in
                    Button {
                        saveToTimeline()
                        saveToNote(note.id)
                        dismiss()
                    } label: {
                        Label(note.title, systemImage: "doc.text")
                    }
                }
            }
        } label: {
            Image(systemName: "doc.text")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .frame(width: 28)
        .help("Also save to a specific note")
    }

    // MARK: - Ask AI Button

    private var askAIButton: some View {
        Button {
            openAIChat()
            dismiss()
        } label: {
            Label("Ask AI", systemImage: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(
            Capsule().fill(Color.primary.opacity(0.06))
        )
        .help("Ask AI about this")
    }

    // MARK: - Actions

    private func saveToTimeline() {
        guard let folderId = browserState.currentFolderId else { return }

        if let text = selectedText {
            TimelineService.shared.appendTextEntry(text: text, url: sourceURL, toFolder: folderId)
        } else if let image = capturedImage {
            TimelineService.shared.appendSnapshotEntry(image: image, url: sourceURL, toFolder: folderId)
        }
    }

    private func saveToNote(_ noteId: UUID) {
        guard let folderId = browserState.currentFolderId else { return }

        if let text = selectedText {
            TimelineService.shared.appendTextEntry(text: text, url: sourceURL, toNote: noteId, inFolder: folderId)
        } else if let image = capturedImage {
            TimelineService.shared.appendSnapshotEntry(image: image, url: sourceURL, toNote: noteId, inFolder: folderId)
        }
    }

    private func openAIChat() {
        guard let activeTab = browserState.activeTab else { return }

        let chatId = activeTab.chatBubbleState.createChat(pageURL: activeTab.url)

        if let text = selectedText {
            let message = BubbleChatMessage(role: .user, content: text)
            activeTab.chatBubbleState.appendMessage(chatId: chatId, message: message)
        } else if let image = capturedImage {
            let domain = sourceURL?.host ?? "page"
            let message = BubbleChatMessage(role: .user, content: "[Snapshot from \(domain)]", image: image)
            activeTab.chatBubbleState.appendMessage(chatId: chatId, message: message)
        }
    }

    private func dismiss() {
        withAnimation(ArcTheme.springAnimation) {
            isVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }

    // MARK: - Helpers

    private func currentFolderNotes() -> [Note] {
        guard let folderId = browserState.currentFolderId else { return [] }
        return NotePersistence.shared.loadAllNotes(forFolder: folderId)
    }

    private func anchorPoint(in geo: GeometryProxy) -> CGPoint? {
        guard let screenPos = screenPosition,
              let window = NSApp.keyWindow
        else { return nil }

        let windowPoint = window.convertPoint(fromScreen: screenPos)

        let viewFrame = geo.frame(in: .global)
        let localX = windowPoint.x - viewFrame.origin.x
        let localY = viewFrame.size.height - (windowPoint.y - viewFrame.origin.y) - 40

        return CGPoint(
            x: max(100, min(localX, viewFrame.width - 100)),
            y: max(30, min(localY, viewFrame.height - 30))
        )
    }
}
