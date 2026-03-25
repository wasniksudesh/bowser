// ChatService.swift - AI Chat Service for Chat Bubbles
// Sends user questions with page URL context to the AI sidecar's LangChain agent

import Foundation

@MainActor
final class ChatService: Sendable {

    static let shared = ChatService()

    private init() {}

    /// Send a chat message with the page URL as context.
    /// Routes through the LangChain AI agent which supports tools and web search.
    func sendMessage(query: String, pageURL: URL, conversationHistory: [BubbleChatMessage] = []) async throws -> String {
        var task = "The user is currently viewing: \(pageURL.absoluteString)\n\n"

        if !conversationHistory.isEmpty {
            task += "Conversation so far:\n"
            for msg in conversationHistory {
                let role = msg.role == .user ? "User" : "Assistant"
                task += "\(role): \(msg.content)\n"
            }
            task += "\n"
        }

        task += "User question: \(query)"

        return try await AIService.shared.executeTask(task: task)
    }
}
