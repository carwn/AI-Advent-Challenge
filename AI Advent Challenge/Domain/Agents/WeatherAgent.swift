//
//  WeatherAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class WeatherAgent: Agent {
    let name = "Агент погоды"
    let icon = "cloud.sun"
    let description = "Специализируется на предоставлении информации о погоде в любом месте"
    var conversation: Conversation

    private let provider: LLMProvider
    private let toolExecutor: ToolExecutor
    private let systemPrompt = "You are a weather assistant. Use the weather tool to provide accurate weather information for any location the user asks about."
    private let availableTools: [ToolDefinition] = [.weatherTool()]
    private let maxTokens = 500
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
