//
//  StepByStepAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class StepByStepAgent: BaseAgent {
    override var name: String { "Пошаговый решатель" }
    override var icon: String { "list.number" }
    override var description: String { "Разбивает любую задачу на последовательные шаги и решает методично" }

    init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: """
                You are a methodical problem-solving assistant. For every user request:
                1. Restate the problem briefly.
                2. Break it down into clear, numbered steps.
                3. Execute each step explicitly, showing your reasoning.
                4. Provide a final summary with the answer.
                Never skip steps. Never jump to conclusions without showing your work.
                Keep each step concise — one or two sentences per step is enough.
                """,
            persistenceKey: "step_by_step_agent"
        )
    }
}
