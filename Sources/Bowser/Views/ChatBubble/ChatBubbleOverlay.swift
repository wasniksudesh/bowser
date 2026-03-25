// ChatBubbleOverlay.swift - Floating Chat Bubble Stack
// Bottom-right overlay with base bubble, conversation stack, and chat panel

import SwiftUI

struct ChatBubbleOverlay: View {

    var chatState: ChatBubbleState
    let tabURL: URL
    @State private var hoveredBubbleId: UUID?

    private let baseBubbleSize: CGFloat = 48
    private let chatBubbleSize: CGFloat = 36
    private let bubbleSpacing: CGFloat = 8
    private let edgeInset: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                    .allowsHitTesting(false)

                HStack(alignment: .bottom, spacing: 12) {
                    if chatState.activeChatId != nil {
                        ChatWindowView(
                            chatState: chatState,
                            availableHeight: geo.size.height
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity),
                            removal: .scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity)
                        ))
                    }

                    bubbleColumn
                }
                .animation(ArcTheme.springAnimation, value: chatState.activeChatId)
                .padding(.trailing, edgeInset)
                .padding(.bottom, edgeInset)
            }
        }
    }

    // MARK: - Bubble Column

    private var bubbleColumn: some View {
        VStack(spacing: bubbleSpacing) {
            if chatState.isExpanded && !chatState.chats.isEmpty {
                collapseButton
                    .transition(.scale.combined(with: .opacity))

                ForEach(chatState.chats) { chat in
                    conversationBubble(chat: chat)
                        .transition(.scale.combined(with: .opacity))
                }
            } else if !chatState.chats.isEmpty {
                expandButton
                    .transition(.scale.combined(with: .opacity))
            }

            baseBubble
        }
        .animation(ArcTheme.springAnimation, value: chatState.isExpanded)
        .animation(ArcTheme.springAnimation, value: chatState.chats.count)
    }

    // MARK: - Base Bubble (+)

    private var baseBubble: some View {
        Button {
            withAnimation(ArcTheme.springAnimation) {
                _ = chatState.createChat(pageURL: tabURL)
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))
                .frame(width: baseBubbleSize, height: baseBubbleSize)
                .background(.thickMaterial, in: RoundedRectangle(cornerRadius: ArcTheme.tabRowCornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ArcTheme.tabRowCornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: ArcTheme.primaryShadow.color, radius: ArcTheme.primaryShadow.radius, y: ArcTheme.primaryShadow.y)
                .shadow(color: ArcTheme.secondaryShadow.color, radius: ArcTheme.secondaryShadow.radius, y: ArcTheme.secondaryShadow.y)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expand / Collapse

    private var expandButton: some View {
        Button {
            withAnimation(ArcTheme.springAnimation) {
                chatState.isExpanded = true
            }
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 20)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var collapseButton: some View {
        Button {
            withAnimation(ArcTheme.springAnimation) {
                chatState.isExpanded = false
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 20)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Conversation Bubble

    private func conversationBubble(chat: BubbleChatConversation) -> some View {
        let isActive = chatState.activeChatId == chat.id
        let isHovered = hoveredBubbleId == chat.id

        return Button {
            withAnimation(ArcTheme.springAnimation) {
                if isActive {
                    chatState.closeChat()
                } else {
                    chatState.openChat(chat.id)
                }
            }
        } label: {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : .primary.opacity(0.85))
                .frame(width: chatBubbleSize, height: chatBubbleSize)
                .background(
                    .thickMaterial,
                    in: RoundedRectangle(cornerRadius: ArcTheme.tabRowCornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ArcTheme.tabRowCornerRadius, style: .continuous)
                        .strokeBorder(
                            isActive ? Color.accentColor.opacity(0.4) : .white.opacity(0.15),
                            lineWidth: isActive ? 1 : 0.5
                        )
                )
                .opacity(isHovered && !isActive ? 0.85 : 1.0)
                .shadow(color: ArcTheme.secondaryShadow.color, radius: ArcTheme.secondaryShadow.radius, y: ArcTheme.secondaryShadow.y)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ArcTheme.hoverAnimation) {
                hoveredBubbleId = hovering ? chat.id : nil
            }
        }
    }
}
