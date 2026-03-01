//
//  GeneralAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class GeneralAgent: BaseAgent {
    override var name: String { "Универсальный ассистент" }
    override var icon: String { "brain" }
    override var description: String { "Универсальный помощник для любых задач" }

    init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: "You are a helpful AI assistant.",
            persistenceKey: "general_agent"
        )
    }
}
