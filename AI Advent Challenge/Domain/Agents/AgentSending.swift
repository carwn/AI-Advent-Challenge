//
//  SendMessageUseCase.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

protocol SendingMessage {
    func execute(
        userText: String,
        conversation: Conversation,
        tools: [ToolDefinition],
        temperature: Double,
        maxTokens: Int,
        stopWords: [String]?
    ) async throws -> Conversation
}

final class SendMessageUseCase: SendingMessage {
    private let provider: LLMProvider
    private let toolExecutor: ToolExecutor

    init(provider: LLMProvider, toolExecutor: ToolExecutor) {
        self.provider = provider
        self.toolExecutor = toolExecutor
    }

    func execute(
        userText: String,
        conversation: Conversation,
        tools: [ToolDefinition],
        temperature: Double,
        maxTokens: Int,
        stopWords: [String]?
    ) async throws -> Conversation {
        var conv = conversation
        conv.addMessage(Message(role: .user, content: userText))

        let startTime = Date()
        let effectiveMaxTokens = max(maxTokens, provider.minMaxTokens)
        let response = try await provider.complete(
            messages: conv.messages.map { $0.toLLMMessage() },
            tools: tools,
            temperature: temperature,
            maxTokens: effectiveMaxTokens,
            stop: stopWords
        )

        let finalResponse: AgentResponse
        if response.requiresToolExecution, let toolCalls = response.message.toolCalls {
            conv.addMessage(Message(
                role: .assistant,
                content: response.message.content,
                toolCalls: response.message.toolCalls
            ))
            for toolCall in toolCalls {
                let result = try await toolExecutor.execute(toolCall)
                conv.addMessage(Message(role: .tool, content: result, toolCallId: toolCall.id))
            }
            finalResponse = try await provider.complete(
                messages: conv.messages.map { $0.toLLMMessage() },
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
            role: .assistant,
            content: src.content,
            toolCalls: src.toolCalls,
            responseTime: elapsed,
            modelName: provider.modelName,
            promptTokens: finalResponse.usage?.promptTokens,
            completionTokens: finalResponse.usage?.completionTokens,
            thoughtsTokens: finalResponse.usage?.thoughtsTokens
        )
        conv.addMessage(timedMessage)

        return conv
    }
}
