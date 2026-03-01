//
//  ContextManagedAgent.swift
//  AI Advent Challenge
//

import Foundation

final class ContextManagedAgent: BaseAgent {
    override var name: String { "Агент с памятью" }
    override var icon: String { "memorychip" }
    override var description: String { "Полная история в UI; в API — краткое содержание вместо уже сжатых сообщений. Сжатие при >1500 токенов." }

    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        conversationId: UUID,
        compressionPolicy: (any ContextCompressionPolicy)? = nil
    ) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: "You are a helpful AI assistant with excellent long-term memory. You always take into account the conversation history provided.",
            conversationId: conversationId,
            compressionPolicy: compressionPolicy
        )
    }
}
