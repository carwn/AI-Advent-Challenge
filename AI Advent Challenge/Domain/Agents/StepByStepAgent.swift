//
//  StepByStepAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class StepByStepAgent: Agent {
    let name = "Пошаговый решатель"
    let icon = "list.number"
    let description = "Разбивает любую задачу на последовательные шаги и решает методично"
    var conversation: Conversation

    private let sendMessage: any SendingMessage
    private let systemPrompt = """
        You are a methodical problem-solving assistant. For every user request:
        1. Restate the problem briefly.
        2. Break it down into clear, numbered steps.
        3. Execute each step explicitly, showing your reasoning.
        4. Provide a final summary with the answer.
        Never skip steps. Never jump to conclusions without showing your work.
        Keep each step concise — one or two sentences per step is enough.
        """
    private let availableTools: [ToolDefinition] = []
    private let maxTokens = 1000
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
