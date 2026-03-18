//
//  SendMessageUseCase.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

protocol SendMessageToLMMUseCase {

    func execute(
        userText: String,
        conversation: Conversation,
        tools: [ToolDefinition],
        temperature: Double,
        maxTokens: Int,
        stopWords: [String]?
    ) async throws -> Conversation
    
    func execute(
        systemPrompt: String,
        userMessage: String,
        tools: [ToolDefinition],
        temperature: Double,
        maxTokens: Int,
        stopWords: [String]?
    ) async throws -> AgentResponse

}

final class SendMessageToLMMInteractor {

    private let provider: LLMProvider
    private let toolExecutor: ToolExecutor

    init(provider: LLMProvider, toolExecutor: ToolExecutor) {
        self.provider = provider
        self.toolExecutor = toolExecutor
    }

    // MARK: - Private

    /// Выполняет запрос к провайдеру, при необходимости обрабатывает tool-вызовы
    /// и повторяет запрос. Мутирует `messages`, добавляя промежуточные сообщения.
    private func completeResolvingTools(
        messages: inout [LLMMessage],
        tools: [ToolDefinition],
        temperature: Double,
        maxTokens: Int,
        stopWords: [String]?
    ) async throws -> AgentResponse {
        let effectiveMaxTokens = max(maxTokens, provider.minMaxTokens)
        let response = try await provider.complete(
            messages: messages,
            tools: tools,
            temperature: temperature,
            maxTokens: effectiveMaxTokens,
            stop: stopWords
        )

        guard response.requiresToolExecution, let toolCalls = response.message.toolCalls else {
            return response
        }

        messages.append(LLMMessage(role: .assistant, content: response.message.content, toolCalls: toolCalls))
        for toolCall in toolCalls {
            let result = try await toolExecutor.execute(toolCall)
            messages.append(LLMMessage(role: .tool, content: result, toolCallId: toolCall.id))
        }

        return try await provider.complete(
            messages: messages,
            tools: tools,
            temperature: temperature,
            maxTokens: effectiveMaxTokens,
            stop: nil
        )
    }
}

extension SendMessageToLMMInteractor: SendMessageToLMMUseCase {
    
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
        var llmMessages = conv.messages.filter { $0.role != .summaryUsage }.map { $0.toLLMMessage() }
        let countBefore = llmMessages.count
        let finalResponse = try await completeResolvingTools(
            messages: &llmMessages,
            tools: tools,
            temperature: temperature,
            maxTokens: maxTokens,
            stopWords: stopWords
        )

        // Синхронизируем промежуточные сообщения (tool-call + tool-result),
        // добавленные хелпером, обратно в conv
        for msg in llmMessages[countBefore...] {
            conv.addMessage(Message(role: msg.role, content: msg.content, toolCalls: msg.toolCalls, toolCallId: msg.toolCallId))
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let src = finalResponse.message
        conv.addMessage(Message(
            role: .assistant,
            content: src.content,
            toolCalls: src.toolCalls,
            responseTime: elapsed,
            modelName: provider.modelName,
            promptTokens: finalResponse.usage?.promptTokens,
            completionTokens: finalResponse.usage?.completionTokens,
            thoughtsTokens: finalResponse.usage?.thoughtsTokens
        ))

        return conv
    }
    
    func execute(
        systemPrompt: String,
        userMessage: String,
        tools: [ToolDefinition],
        temperature: Double,
        maxTokens: Int,
        stopWords: [String]?
    ) async throws -> AgentResponse {
        var messages = [
            LLMMessage(role: .system, content: systemPrompt),
            LLMMessage(role: .user, content: userMessage)
        ]
        var response = try await completeResolvingTools(
            messages: &messages,
            tools: tools,
            temperature: temperature,
            maxTokens: maxTokens,
            stopWords: stopWords
        )
        response.modelName = provider.modelName
        return response
    }
    
}
