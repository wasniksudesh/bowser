//
//  AgentChatBarView.swift
//  Bowser
//
//  Glassmorphism-styled chat bar for Agent Mode
//  Pinned to the bottom of the main view
//

import SwiftUI

// =============================================================================
// MARK: - Agent Chat Bar View
// =============================================================================

/// Glassmorphism-styled chat input bar
/// Pinned to bottom of Agent Mode main view
struct AgentChatBarView: View {
    
    @Bindable var browserState: BrowserState
    
    @State private var inputText: String = ""
    @State private var isHovering: Bool = false
    
    private var agentState: AgentState {
        browserState.agentState
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Text input field
            TextField("Ask the agent...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .onSubmit {
                    submitQuery()
                }

            // Voice dictation
            VoiceInputButton(text: $inputText)
                .padding(.leading, -4)

            // Send button
            Button(action: submitQuery) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.gray
                            : Color.blue
                    )
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agentState.isLoading)
            .padding(.trailing, 8)
        }
        .background(
            // Glassmorphism effect
            ZStack {
                // Blur background
                // .ultraThinMaterial
                
                // Subtle gradient overlay
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.1),
                        Color.white.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .overlay(
            // Border with subtle glow
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isHovering ? 0.3 : 0.2),
                            Color.white.opacity(isHovering ? 0.2 : 0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(
            color: Color.black.opacity(0.1),
            radius: 20,
            y: 10
        )
        .shadow(
            color: Color.black.opacity(0.05),
            radius: 5,
            y: 2
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isHovering)
    }
    
    // MARK: - Actions
    
    private func submitQuery() {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        
        // Clear input immediately
        inputText = ""
        
        // Submit query
        Task {
            await agentState.submitQuery(query)
        }
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct AgentChatBarView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Background to show glassmorphism effect
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack {
                Spacer()
                
                AgentChatBarView(browserState: BrowserState())
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .frame(width: 600, height: 400)
    }
}
#endif
