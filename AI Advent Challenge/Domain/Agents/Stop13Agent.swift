//
//  Stop13Agent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class Stop13Agent: BaseAgent {
    override var name: String { "Агент-Трискаидекафоб" }
    override var icon: String { "hand.raised" }
    override var description: String { "Панически боится числа 13 и останавливает генерацию при его упоминании" }
    override var stopWords: [String]? { ["13"] }

    init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: "You are a helpful assistant. Answer any question freely and in detail.",
            persistenceKey: "stop13_agent"
        )
    }
}
