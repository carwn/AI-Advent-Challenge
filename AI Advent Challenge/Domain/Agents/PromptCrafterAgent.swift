//
//  PromptCrafterAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class PromptCrafterAgent: Agent {
    let name = "Промпт-инженер"
    let icon = "text.cursor"
    let description = "Составляет оптимальный промпт для другого AI-агента"
    var conversation: Conversation

    private let sendMessage: any SendingMessage
    private let systemPrompt = """
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
        """
    private let availableTools: [ToolDefinition] = []
    private let maxTokens = 800
    private let stopWords: [String]? = nil
    private let temperature: Double = 0.7

    init(sendMessage: any SendingMessage) {
        self.sendMessage = sendMessage
        self.conversation = Conversation(systemPrompt: systemPrompt)
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
    }

    func clearConversation() {
        conversation = Conversation(systemPrompt: systemPrompt)
    }
}
