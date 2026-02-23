//
//  GeneralAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class GeneralAgent: Agent {
    let name = "Универсальный ассистент"
    let icon = "brain"
    let description = "Универсальный помощник для любых задач"
    var conversation: Conversation

    private let provider: LLMProvider
    private let toolExecutor: ToolExecutor
    private let systemPrompt = "You are a helpful AI assistant."
    private let availableTools: [ToolDefinition] = []
    private let maxTokens = 1000
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
