//
//  MultiExpertAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class MultiExpertAgent: Agent {
    let name = "Совет экспертов"
    let icon = "person.3"
    let description = "Привлекает трёх экспертов, получает их мнения и синтезирует вывод"
    var conversation: Conversation

    private let sendMessage: any SendMessageToLMMUseCase
    private let persistence: ConversationPersistenceService
    private let systemPrompt = """
        You are a multi-expert reasoning system. For every user request:

        1. **Identify Experts**: Determine 3 distinct expert roles most relevant to the task. Name each role clearly.

        2. **Expert Opinions**: For each expert, present their analysis in this format:
           ### [Expert Role]
           [Their perspective, reasoning, and recommendation]

        3. **Synthesis**: After all three opinions, add a section:
           ### Итоговый вывод
           Synthesize the key insights from all three experts into a final, balanced conclusion.

        Always complete all three expert opinions before synthesizing.
        Keep each expert's opinion concise — 3–5 sentences maximum per expert.
        """
    private let availableTools: [ToolDefinition] = []
    private let maxTokens = 2000
    private let stopWords: [String]? = nil
    private let temperature: Double = 0.5
    private let persistenceKey = "multi_expert_agent"

    init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService) {
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
