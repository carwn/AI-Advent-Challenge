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

    func sendMessage(
        _ content: String,
        in conversation: Conversation
    ) async throws -> AgentResponse

    func executeToolsAndContinue(
        _ response: AgentResponse,
        in conversation: Conversation
    ) async throws -> AgentResponse
}

// Default implementation
extension Agent {
    func sendMessage(
        _ content: String,
        in conversation: Conversation
    ) async throws -> AgentResponse {
        let userMessage = Message(role: .user, content: content)
        var updatedConversation = conversation
        updatedConversation.addMessage(userMessage)

        let response = try await provider.complete(
            messages: updatedConversation.messages,
            tools: agentType.availableTools,
            temperature: 0.7,
            maxTokens: nil
        )

        return response
    }

    func executeToolsAndContinue(
        _ response: AgentResponse,
        in conversation: Conversation
    ) async throws -> AgentResponse {
        guard response.requiresToolExecution,
              let toolCalls = response.message.toolCalls else {
            return response
        }

        var updatedConversation = conversation
        updatedConversation.addMessage(response.message)

        // Execute all tool calls
        for toolCall in toolCalls {
            let result = try await toolExecutor.execute(toolCall)
            let toolMessage = Message(
                role: .tool,
                content: result,
                toolCallId: toolCall.id
            )
            updatedConversation.addMessage(toolMessage)
        }

        // Continue conversation with tool results
        let finalResponse = try await provider.complete(
            messages: updatedConversation.messages,
            tools: agentType.availableTools,
            temperature: 0.7,
            maxTokens: nil
        )

        return finalResponse
    }
}

// Concrete implementation
final class DefaultAgent: Agent {
    let agentType: AgentType
    let provider: LLMProvider
    let toolExecutor: ToolExecutor

    init(agentType: AgentType, provider: LLMProvider, toolExecutor: ToolExecutor) {
        self.agentType = agentType
        self.provider = provider
        self.toolExecutor = toolExecutor
    }
}
