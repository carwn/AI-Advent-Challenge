//
//  LLMProvider.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

/// Единица потокового ответа от LLM-провайдера.
enum StreamChunk {
    case thinking(String)   // Токен размышлений (reasoning)
    case content(String)    // Токен ответа
    case usage(UsageInfo)   // Финальная статистика токенов
}

protocol LLMProvider {
    var modelName: String { get }
    /// Минимальный бюджет токенов для моделей с thinking (thinking съедает часть maxOutputTokens).
    /// Агент использует max(agentType.maxTokens, provider.minMaxTokens).
    var minMaxTokens: Int { get }
    /// Поддерживает ли провайдер нативный стриминг (SSE).
    var supportsStreaming: Bool { get }

    func complete(
        messages: [LLMMessage],
        tools: [ToolDefinition]?,
        temperature: Double,
        maxTokens: Int?,
        stop: [String]?
    ) async throws -> AgentResponse

    func streamComplete(
        messages: [LLMMessage],
        tools: [ToolDefinition]?,
        temperature: Double,
        maxTokens: Int?,
        stop: [String]?
    ) -> AsyncThrowingStream<StreamChunk, Error>
}

extension LLMProvider {
    var minMaxTokens: Int { 0 }
    var supportsStreaming: Bool { false }

    /// Default-реализация: оборачивает complete() в поток.
    /// Провайдеры без нативного стриминга получают поведение «всё сразу».
    func streamComplete(
        messages: [LLMMessage],
        tools: [ToolDefinition]?,
        temperature: Double,
        maxTokens: Int?,
        stop: [String]?
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await complete(
                        messages: messages, tools: tools,
                        temperature: temperature, maxTokens: maxTokens, stop: stop
                    )
                    if let reasoning = response.message.reasoning, !reasoning.isEmpty {
                        continuation.yield(.thinking(reasoning))
                    }
                    continuation.yield(.content(response.message.content))
                    if let usage = response.usage {
                        continuation.yield(.usage(usage))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
