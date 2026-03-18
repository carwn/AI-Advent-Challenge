//
//  AgentResponse.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

struct AgentResponse {
    let message: LLMResponse
    let requiresToolExecution: Bool
    let finishReason: FinishReason
    let usage: UsageInfo?
    var modelName: String? = nil
}

enum FinishReason: String {
    case stop
    case toolCalls = "tool_calls"
    case length
    case contentFilter = "content_filter"
}

struct UsageInfo {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    let thoughtsTokens: Int?
}
