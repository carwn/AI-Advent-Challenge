//
//  StickyFactsAgent.swift
//  AI Advent Challenge
//

import Foundation

final class StickyFactsAgent: BaseAgent {
    override var name: String { "Агент с фактами" }
    override var icon: String { "tag.fill" }
    override var description: String { "Извлекает ключевые факты (цель, предпочтения, решения) после каждого сообщения. В API отправляет: факты + последние 10 сообщений." }

    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        conversationId: UUID,
        compressionPolicy: (any ContextCompressionPolicy)? = nil
    ) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: "You are a helpful AI assistant with a structured memory. You always remember important facts about the user's goals, preferences, constraints, and decisions from the conversation.",
            conversationId: conversationId,
            compressionPolicy: compressionPolicy
        )
    }
}
