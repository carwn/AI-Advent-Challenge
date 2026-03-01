//
//  BulletListAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class BulletListAgent: BaseAgent {
    override var name: String { "Агент-список" }
    override var icon: String { "list.bullet" }
    override var description: String { "Отвечает на любой вопрос в виде списка до 5 ключевых пунктов" }
    override var maxTokens: Int { 300 }

    init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: "You are a concise assistant. Always respond using a bullet list with a maximum of 5 items. Each item must be short and clear. Never use prose, paragraphs, or more than 5 bullets. If the answer requires more than 5 points, pick the most important ones.",
            persistenceKey: "bullet_list_agent"
        )
    }
}
