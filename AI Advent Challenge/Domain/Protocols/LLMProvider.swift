//
//  LLMProvider.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

protocol LLMProvider {
    var modelName: String { get }

    func complete(
        messages: [Message],
        tools: [ToolDefinition]?,
        temperature: Double,
        maxTokens: Int?
    ) async throws -> AgentResponse
}
