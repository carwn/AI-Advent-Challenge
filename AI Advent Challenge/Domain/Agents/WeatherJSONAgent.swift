//
//  WeatherJSONAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class WeatherJSONAgent: Agent {
    let name = "Агент погоды (JSON)"
    let icon = "cloud.sun.fill"
    let description = "Возвращает информацию о погоде в виде структурированного JSON-объекта"
    var conversation: Conversation

    private let provider: LLMProvider
    private let toolExecutor: ToolExecutor
    private let systemPrompt = """
        You are a weather assistant that always responds in JSON format. Use the weather tool to get weather data, then return your entire response as a valid JSON object.
        The JSON must include the following fields:
        - "location": the requested location
        - "temperature": temperature value as a number
        - "condition": weather condition as a string
        - "humidity": humidity percentage as a number
        - "summary": a brief human-readable description
        Never include any text outside of the JSON object.
        """
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
