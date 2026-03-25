// ChatBubbleState.swift - Per-Tab AI Chat Bubble State
// Manages multiple AI chat conversations scoped to a single browser tab

import Foundation

// =============================================================================
// MARK: - Bubble Message Role
// =============================================================================

enum BubbleMessageRole: Sendable {
    case user
    case assistant
}

// =============================================================================
// MARK: - Bubble Chat Message
// =============================================================================

struct BubbleChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: BubbleMessageRole
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: BubbleMessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// =============================================================================
// MARK: - Bubble Chat Conversation
// =============================================================================

struct BubbleChatConversation: Identifiable, Sendable {
    let id: UUID
    var messages: [BubbleChatMessage]
    let createdAt: Date
    let pageURL: URL
    var isLoading: Bool

    init(id: UUID = UUID(), pageURL: URL) {
        self.id = id
        self.messages = []
        self.createdAt = Date()
        self.pageURL = pageURL
        self.isLoading = false
    }
}

// =============================================================================
// MARK: - Chat Bubble State (Per-Tab)
// =============================================================================

@Observable
@MainActor
final class ChatBubbleState {
    var chats: [BubbleChatConversation] = []
    var activeChatId: UUID? = nil
    var isExpanded: Bool = false

    nonisolated init() {}

    var activeChat: BubbleChatConversation? {
        guard let id = activeChatId else { return nil }
        return chats.first { $0.id == id }
    }

    func createChat(pageURL: URL) -> UUID {
        let chat = BubbleChatConversation(pageURL: pageURL)
        chats.append(chat)
        activeChatId = chat.id
        isExpanded = true
        return chat.id
    }

    func openChat(_ id: UUID) {
        activeChatId = id
    }

    func closeChat() {
        activeChatId = nil
    }

    func appendMessage(chatId: UUID, message: BubbleChatMessage) {
        guard let index = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[index].messages.append(message)
    }

    func setLoading(chatId: UUID, _ loading: Bool) {
        guard let index = chats.firstIndex(where: { $0.id == chatId }) else { return }
        chats[index].isLoading = loading
    }

    func deleteChat(_ id: UUID) {
        if activeChatId == id {
            activeChatId = nil
        }
        chats.removeAll { $0.id == id }
        if chats.isEmpty {
            isExpanded = false
        }
    }
}
