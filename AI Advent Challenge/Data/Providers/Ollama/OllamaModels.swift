//
//  OllamaModels.swift
//  AI Advent Challenge
//
//  Created by Claude on 24.03.2026.
//

import Foundation

// MARK: - Request

struct OllamaRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let tools: [ToolDefinition]?
    let temperature: Double
    let maxTokens: Int?
    let stop: [String]?
    let stream: Bool
    enum CodingKeys: String, CodingKey {
        case model, messages, tools, temperature, stop, stream
        case maxTokens = "max_tokens"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encode(temperature, forKey: .temperature)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(stop, forKey: .stop)
        try container.encode(stream, forKey: .stream)
    }
}

// MARK: - Non-streaming response

/// Ответ Ollama при stream=false.
/// Расширяет стандартный OpenAI-формат полем reasoning в message.
struct OllamaResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let message: OllamaMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    struct OllamaMessage: Decodable {
        let role: String
        let content: String?
        let reasoning: String?
        let toolCalls: [ToolCall]?

        enum CodingKeys: String, CodingKey {
            case role, content, reasoning
            case toolCalls = "tool_calls"
        }
    }

    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    func toAgentResponse() -> AgentResponse {
        let choice = choices[0]
        let message = LLMResponse(
            content: choice.message.content ?? "",
            toolCalls: choice.message.toolCalls,
            reasoning: choice.message.reasoning
        )
        let finishReason = FinishReason(rawValue: choice.finishReason ?? "stop") ?? .stop
        let usageInfo = usage.map {
            UsageInfo(
                promptTokens: $0.promptTokens,
                completionTokens: $0.completionTokens,
                totalTokens: $0.totalTokens,
                thoughtsTokens: nil
            )
        }
        return AgentResponse(
            message: message,
            requiresToolExecution: choice.message.toolCalls != nil,
            finishReason: finishReason,
            usage: usageInfo
        )
    }
}

// MARK: - Streaming chunk

/// Один SSE-чанк при stream=true.
/// Ollama отдаёт reasoning и content как дельты (каждый чанк — новая часть).
struct OllamaStreamChunk: Decodable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let content: String?
        let reasoning: String?
    }

    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}
