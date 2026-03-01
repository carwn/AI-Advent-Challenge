//
//  LLMProvider.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

protocol LLMProvider {
    var modelName: String { get }
    /// Минимальный бюджет токенов для моделей с thinking (thinking съедает часть maxOutputTokens).
    /// Агент использует max(agentType.maxTokens, provider.minMaxTokens).
    var minMaxTokens: Int { get }

    func complete(
        messages: [LLMMessage],
        tools: [ToolDefinition]?,
        temperature: Double,
        maxTokens: Int?,
        stop: [String]?
    ) async throws -> AgentResponse
}

extension LLMProvider {
    var minMaxTokens: Int { 0 }
}
