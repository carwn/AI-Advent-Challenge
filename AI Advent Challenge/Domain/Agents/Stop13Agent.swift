//
//  Stop13Agent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class Stop13Agent: Agent {
    let name = "Агент-Трискаидекафоб"
    let icon = "hand.raised"
    let description = "Панически боится числа 13 и останавливает генерацию при его упоминании"
    var conversation: Conversation

    private let provider: LLMProvider
    private let toolExecutor: ToolExecutor
    private let systemPrompt = "You are a helpful assistant. Answer any question freely and in detail."
    private let availableTools: [ToolDefinition] = []
    private let maxTokens = 1000
    private let stopWords: [String]? = ["13"]
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
