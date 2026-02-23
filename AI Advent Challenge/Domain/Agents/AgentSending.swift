//
//  AgentSending.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

enum AgentSending {
    static func send(
        userText: String,
        conversation: Conversation,
        provider: LLMProvider,
        tools: [ToolDefinition],
        temperature: Double,
        maxTokens: Int,
        stopWords: [String]?,
        toolExecutor: ToolExecutor
    ) async throws -> (AgentResponse, Conversation) {
        var conv = conversation
        conv.addMessage(Message(role: .user, content: userText))

        let startTime = Date()
        let effectiveMaxTokens = max(maxTokens, provider.minMaxTokens)
        let response = try await provider.complete(
            messages: conv.messages,
            tools: tools,
            temperature: temperature,
            maxTokens: effectiveMaxTokens,
            stop: stopWords
        )

        let finalResponse: AgentResponse
        if response.requiresToolExecution, let toolCalls = response.message.toolCalls {
            conv.addMessage(response.message)
            for toolCall in toolCalls {
                let result = try await toolExecutor.execute(toolCall)
                conv.addMessage(Message(role: .tool, content: result, toolCallId: toolCall.id))
            }
            finalResponse = try await provider.complete(
                messages: conv.messages,
                tools: tools,
                temperature: temperature,
                maxTokens: effectiveMaxTokens,
                stop: nil
            )
        } else {
            finalResponse = response
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let src = finalResponse.message
        let timedMessage = Message(
            id: src.id,
            role: src.role,
            content: src.content,
            timestamp: src.timestamp,
            toolCalls: src.toolCalls,
            toolCallId: src.toolCallId,
            responseTime: elapsed,
            modelName: provider.modelName,
            promptTokens: finalResponse.usage?.promptTokens,
            completionTokens: finalResponse.usage?.completionTokens,
            thoughtsTokens: finalResponse.usage?.thoughtsTokens
        )
        conv.addMessage(timedMessage)

        return (finalResponse, conv)
    }
}
