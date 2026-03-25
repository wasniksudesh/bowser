// ChatWindowView.swift - Semi-Transparent AI Chat Panel
// AWS-style chat widget themed to ArcTheme

import SwiftUI

struct ChatWindowView: View {

    var chatState: ChatBubbleState
    let availableHeight: CGFloat

    @State private var inputText: String = ""
    @State private var lastActiveChatId: UUID?
    @FocusState private var isInputFocused: Bool

    private let panelWidth: CGFloat = 360

    private var panelHeight: CGFloat {
        min(availableHeight * 0.5, 480)
    }

    private var chat: BubbleChatConversation? {
        chatState.activeChat
    }

    private var pageDomain: String {
        guard let host = chat?.pageURL.host else { return "New Tab" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().opacity(0.3)
            messageList
            Divider().opacity(0.3)
            inputSection
        }
        .frame(width: panelWidth, height: panelHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ArcTheme.cardCornerRadius, style: .continuous))
        .shadow(color: ArcTheme.primaryShadow.color, radius: ArcTheme.primaryShadow.radius, y: ArcTheme.primaryShadow.y)
        .shadow(color: ArcTheme.secondaryShadow.color, radius: ArcTheme.secondaryShadow.radius, y: ArcTheme.secondaryShadow.y)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Ask AI")
                    .font(ArcTheme.sectionHeaderFont)
                    .foregroundStyle(.primary)
                Text(pageDomain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                withAnimation(ArcTheme.springAnimation) {
                    chatState.closeChat()
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(.quaternary.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)

            Button {
                guard let id = chatState.activeChatId else { return }
                withAnimation(ArcTheme.springAnimation) {
                    chatState.deleteChat(id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(.quaternary.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [ArcTheme.highlightColor.opacity(0.06), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if let chat, chat.messages.isEmpty && !chat.isLoading {
                        emptyState
                    }

                    if let chat {
                        ForEach(chat.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }

                        if chat.isLoading {
                            loadingIndicator
                                .id("loading")
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: chat?.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: chat?.isLoading) { _, isLoading in
                if isLoading == true {
                    withAnimation {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                } else {
                    scrollToBottom(proxy: proxy)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 24))
                .foregroundStyle(.quaternary)
            Text("Ask anything about this page")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var loadingIndicator: some View {
        HStack(spacing: 4) {
            ProgressView()
                .controlSize(.small)
            Text("Thinking...")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Input

    private var inputSection: some View {
        HStack(spacing: 8) {
            TextField("Ask a question...", text: $inputText)
                .textFieldStyle(.plain)
                .font(ArcTheme.tabTitleFont)
                .focused($isInputFocused)
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary.opacity(0.4) : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear {
            isInputFocused = true
            lastActiveChatId = chatState.activeChatId
        }
        .onChange(of: chatState.activeChatId) { _, newId in
            if newId != lastActiveChatId {
                inputText = ""
                lastActiveChatId = newId
                isInputFocused = true
            }
        }
    }

    // MARK: - Helpers

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastId = chat?.messages.last?.id {
            withAnimation {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let chat else { return }

        let chatId = chat.id
        let pageURL = chat.pageURL
        let history = chat.messages

        let userMessage = BubbleChatMessage(role: .user, content: text)
        chatState.appendMessage(chatId: chatId, message: userMessage)
        inputText = ""
        chatState.setLoading(chatId: chatId, true)

        Task {
            do {
                let response = try await ChatService.shared.sendMessage(
                    query: text,
                    pageURL: pageURL,
                    conversationHistory: history
                )
                let assistantMessage = BubbleChatMessage(role: .assistant, content: response)
                chatState.appendMessage(chatId: chatId, message: assistantMessage)
            } catch {
                let errorMessage = BubbleChatMessage(role: .assistant, content: "Sorry, I couldn't get a response. \(error.localizedDescription)")
                chatState.appendMessage(chatId: chatId, message: errorMessage)
            }
            chatState.setLoading(chatId: chatId, false)
        }
    }
}

// =============================================================================
// MARK: - Message Bubble
// =============================================================================

private struct MessageBubbleView: View {

    let message: BubbleChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            Text(message.content)
                .font(ArcTheme.tabTitleFont)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var bubbleBackground: some ShapeStyle {
        message.role == .user
            ? AnyShapeStyle(ArcTheme.activeTabBackground)
            : AnyShapeStyle(Color.primary.opacity(0.05))
    }
}
