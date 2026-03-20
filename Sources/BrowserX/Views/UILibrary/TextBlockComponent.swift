//
//  TextBlockComponent.swift
//  Bowser
//
//  Rich text/markdown block component
//  Part of UILibrary for agent output rendering
//

import SwiftUI

// =============================================================================
// MARK: - Text Block Data Models
// =============================================================================

enum TextFormat: String, Codable {
    case plain
    case markdown
    case code
}

struct TextBlockData {
    let content: String
    let format: TextFormat
}

// =============================================================================
// MARK: - Text Block Component
// =============================================================================

/// Rich text/markdown block for agent text output
struct TextBlockComponent: View {
    
    let data: TextBlockData?
    let isLoading: Bool
    
    @State private var isCopied: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                loadingState
            } else if let data = data {
                textContent(data: data)
            } else {
                emptyState
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }
    
    // MARK: - Text Content
    
    private func textContent(data: TextBlockData) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            // Copy button
            HStack {
                Spacer()
                
                Button(action: {
                    copyToClipboard(data.content)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(isCopied ? .green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .controlColor).opacity(0.3))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            
            // Text content
            ScrollView {
                Group {
                    switch data.format {
                    case .plain:
                        plainText(content: data.content)
                    case .markdown:
                        markdownText(content: data.content)
                    case .code:
                        codeText(content: data.content)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(maxHeight: 400)
        }
    }
    
    // MARK: - Text Formats
    
    private func plainText(content: String) -> some View {
        Text(content)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
    }
    
    private func markdownText(content: String) -> some View {
        // For now, render as plain text
        // In production, you'd use a markdown parser
        Text(content)
            .font(.system(size: 13))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
    }
    
    private func codeText(content: String) -> some View {
        Text(content)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
    }
    
    // MARK: - Copy Action
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        isCopied = true
        
        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }
    
    // MARK: - Loading State
    
    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            
            Text("Loading text...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("No content")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================

#if DEBUG
struct TextBlockComponent_Previews: PreviewProvider {
    static var previews: some View {
        let plainData = TextBlockData(
            content: "This is a plain text block with some content. It can span multiple lines and will be displayed with standard formatting.",
            format: .plain
        )
        
        let codeData = TextBlockData(
            content: """
            function hello() {
                console.log("Hello, world!");
                return 42;
            }
            """,
            format: .code
        )
        
        return VStack(spacing: 20) {
            Text("Plain Text")
                .font(.headline)
            TextBlockComponent(data: plainData, isLoading: false)
            
            Text("Code Block")
                .font(.headline)
            TextBlockComponent(data: codeData, isLoading: false)
        }
        .padding(20)
        .frame(width: 600)
    }
}
#endif
