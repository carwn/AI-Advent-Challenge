//
//  Stop13Agent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class Stop13Agent: Agent {
    let name = "Агент-Трискаидекафоб"
    let icon = "hand.raised"
    let description = "Панически боится числа 13 и останавливает генерацию при его упоминании"
    var conversation: Conversation

    private let sendMessage: any SendingMessage
    private let persistence: ConversationPersistenceService
    private let systemPrompt = "You are a helpful assistant. Answer any question freely and in detail."
    private let availableTools: [ToolDefinition] = []
    private let maxTokens = 1000
    private let stopWords: [String]? = ["13"]
    private let temperature: Double = 0.7
    private let persistenceKey = "stop13_agent"

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
