//
//  SlidingWindowAgent.swift
//  AI Advent Challenge
//

import Foundation

final class SlidingWindowAgent: BaseAgent {
    override var name: String { "Агент скользящего окна" }
    override var icon: String { "rectangle.3.offgrid" }
    override var description: String { "В API отправляются только последние 5 сообщений. Экономит токены, но не помнит начало разговора." }

    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        compressionPolicy: (any ContextCompressionPolicy)? = nil
    ) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: "You are a helpful AI assistant. Answer concisely and clearly.",
            persistenceKey: "sliding_window_agent",
            compressionPolicy: compressionPolicy
        )
    }
}
