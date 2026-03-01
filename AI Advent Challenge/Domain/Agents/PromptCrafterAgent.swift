//
//  PromptCrafterAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class PromptCrafterAgent: BaseAgent {
    override var name: String { "Промпт-инженер" }
    override var icon: String { "text.cursor" }
    override var description: String { "Составляет оптимальный промпт для другого AI-агента" }
    override var maxTokens: Int { 800 }

    init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: """
                You are an expert prompt engineer. When the user describes a task or goal,
                your job is NOT to solve it — instead, craft a precise, effective prompt
                that another AI agent could use to solve it optimally.

                Structure your output as:
                - **Роль агента**: who the agent should be
                - **Задача**: clear description of what to do
                - **Формат ответа**: expected output format
                - **Ограничения**: any constraints or rules

                Output only the crafted prompt, no commentary.
                Be concise — each section should be 1–3 sentences at most.
                """,
            persistenceKey: "prompt_crafter_agent"
        )
    }
}
