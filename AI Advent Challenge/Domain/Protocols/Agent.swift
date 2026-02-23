//
//  Agent.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

protocol Agent {
    var agentType: AgentType { get }
    var provider: LLMProvider { get }
    var toolExecutor: ToolExecutor { get }
    var temperature: Double { get }

    func sendMessage(
        conversation: Conversation
    ) async throws -> AgentResponse

    func executeToolsAndContinue(
        _ response: AgentResponse,
        updating conversation: inout Conversation
    ) async throws -> AgentResponse
}

// Default implementation
extension Agent {
    func sendMessage(
        conversation: Conversation
    ) async throws -> AgentResponse {
        let effectiveMaxTokens = max(agentType.maxTokens, provider.minMaxTokens)
        let response = try await provider.complete(
            messages: conversation.messages,
            tools: agentType.availableTools,
            temperature: temperature,
            maxTokens: effectiveMaxTokens,
            stop: agentType.stopWords
        )

        return response
    }

    func executeToolsAndContinue(
        _ response: AgentResponse,
        updating conversation: inout Conversation
    ) async throws -> AgentResponse {
        guard response.requiresToolExecution,
              let toolCalls = response.message.toolCalls else {
            return response
        }

        // Execute all tool calls and add results directly to the caller's conversation
        for toolCall in toolCalls {
            let result = try await toolExecutor.execute(toolCall)
            let toolMessage = Message(
                role: .tool,
                content: result,
                toolCallId: toolCall.id
            )
            conversation.addMessage(toolMessage)
        }

        let effectiveMaxTokens = max(agentType.maxTokens, provider.minMaxTokens)
        // Continue conversation with tool results
        let finalResponse = try await provider.complete(
            messages: conversation.messages,
            tools: agentType.availableTools,
            temperature: temperature,
            maxTokens: effectiveMaxTokens,
            stop: nil
        )

        return finalResponse
    }
}

// Concrete implementation
final class DefaultAgent: Agent {
    let agentType: AgentType
    let provider: LLMProvider
    let toolExecutor: ToolExecutor
    private let temperatureStore: TemperatureStore

    var temperature: Double { temperatureStore.temperature }

    init(agentType: AgentType, provider: LLMProvider, toolExecutor: ToolExecutor, temperatureStore: TemperatureStore) {
        self.agentType = agentType
        self.provider = provider
        self.toolExecutor = toolExecutor
        self.temperatureStore = temperatureStore
    }
}
