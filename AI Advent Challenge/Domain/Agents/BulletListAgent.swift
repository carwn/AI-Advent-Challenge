//
//  BulletListAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class BulletListAgent: Agent {
    let name = "Агент-список"
    let icon = "list.bullet"
    let description = "Отвечает на любой вопрос в виде списка до 5 ключевых пунктов"
    var conversation: Conversation

    private let sendMessage: any SendingMessage
    private let persistence: ConversationPersistenceService
    private let systemPrompt = "You are a concise assistant. Always respond using a bullet list with a maximum of 5 items. Each item must be short and clear. Never use prose, paragraphs, or more than 5 bullets. If the answer requires more than 5 points, pick the most important ones."
    private let availableTools: [ToolDefinition] = []
    private let maxTokens = 300
    private let stopWords: [String]? = nil
    private let temperature: Double = 0.7
    private let persistenceKey = "bullet_list_agent"

    init(sendMessage: any SendingMessage, persistence: ConversationPersistenceService) {
        self.sendMessage = sendMessage
        self.persistence = persistence
        self.conversation = Conversation(systemPrompt: systemPrompt)
        if let saved = persistence.load(forKey: persistenceKey) {
            self.conversation = saved
        }
    }

    func send(_ text: String) async throws {
        conversation = try await sendMessage.execute(
            userText: text,
            conversation: conversation,
            tools: availableTools,
            temperature: temperature,
            maxTokens: maxTokens,
            stopWords: stopWords
        )
        persistence.save(conversation, forKey: persistenceKey)
    }

    func clearConversation() {
        conversation = Conversation(systemPrompt: systemPrompt)
        persistence.delete(forKey: persistenceKey)
    }
}
