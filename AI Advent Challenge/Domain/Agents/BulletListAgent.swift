//
//  BulletListAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class BulletListAgent: Agent {
    let name = "Агент-список"
    let icon = "list.bullet"
    let description = "Отвечает на любой вопрос в виде списка до 5 ключевых пунктов"
    var conversation: Conversation

    private let provider: LLMProvider
    private let toolExecutor: ToolExecutor
    private let systemPrompt = "You are a concise assistant. Always respond using a bullet list with a maximum of 5 items. Each item must be short and clear. Never use prose, paragraphs, or more than 5 bullets. If the answer requires more than 5 points, pick the most important ones."
    private let availableTools: [ToolDefinition] = []
    private let maxTokens = 300
    private let stopWords: [String]? = nil
    private let temperature: Double = 0.7

    init(provider: LLMProvider, toolExecutor: ToolExecutor) {
        self.provider = provider
        self.toolExecutor = toolExecutor
        self.conversation = Conversation(systemPrompt: systemPrompt)
    }

    func send(_ text: String) async throws -> AgentResponse {
        let (response, updated) = try await AgentSending.send(
            userText: text,
            conversation: conversation,
            provider: provider,
            tools: availableTools,
            temperature: temperature,
            maxTokens: maxTokens,
            stopWords: stopWords,
            toolExecutor: toolExecutor
        )
        conversation = updated
        return response
    }

    func clearConversation() {
        conversation = Conversation(systemPrompt: systemPrompt)
    }
}
