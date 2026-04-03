// VoiceInputButton.swift - Reusable microphone dictation button
// Drops in next to any TextField/TextEditor. Tap to start dictation,
// tap again to stop. Transcribed text is appended to the Binding<String>.

import SwiftUI

// =============================================================================
// MARK: - Voice Input Button
// =============================================================================

/// A compact mic button that uses `VoiceInputService` to append dictated
/// text into a `Binding<String>`. Toggle behaviour: tap = start, tap = stop.
///
/// Usage:
/// ```swift
/// HStack {
///     TextField("Search...", text: $query)
///     VoiceInputButton(text: $query)
/// }
/// ```
struct VoiceInputButton: View {

    /// The text binding to append transcribed speech into.
    @Binding var text: String

    /// Optional override to replace text instead of appending.
    var replaceMode: Bool = false

    @State private var showError = false

    private var service: VoiceInputService { VoiceInputService.shared }
    private var isListening: Bool { service.isListening }

    var body: some View {
        Button(action: toggleListening) {
            ZStack {
                if isListening {
                    Circle()
                        .stroke(Color.red.opacity(0.35), lineWidth: 1.5)
                        .scaleEffect(1.6)
                        .opacity(0)
                        .animation(
                            .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                            value: isListening
                        )
                }

                Image(systemName: isListening ? "mic.fill" : "mic")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isListening ? Color.red : Color.secondary)
                    .symbolEffect(.pulse, isActive: isListening)
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help(isListening ? "Stop dictation (⌘⇧D)" : "Start dictation (⌘⇧D)")
        .alert("Microphone Access", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(service.errorMessage ?? "Could not access microphone.")
        }
        .onChange(of: service.errorMessage) { _, msg in
            if msg != nil { showError = true }
        }
    }

    // MARK: - Actions

    private func toggleListening() {
        if isListening {
            service.stopListening()
        } else {
            service.startListening { chunk in
                if replaceMode {
                    text = chunk
                } else {
                    if text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") {
                        text += chunk
                    } else {
                        text += " " + chunk
                    }
                }
            }
        }
    }
}
