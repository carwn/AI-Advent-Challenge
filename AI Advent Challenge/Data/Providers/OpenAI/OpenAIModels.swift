//
//  OpenAIModels.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

struct OpenAIRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
    let tools: [ToolDefinition]?
    let temperature: Double
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case tools
        case temperature
        case maxTokens = "max_tokens"
    }
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String?
    let toolCalls: [ToolCall]?
    let toolCallId: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
        case name
    }
}

struct OpenAIResponse: Decodable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let index: Int
        let message: OpenAIMessage
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
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
        let message = Message(
            role: MessageRole(rawValue: choice.message.role) ?? .assistant,
            content: choice.message.content ?? "",
            toolCalls: choice.message.toolCalls
        )

        let finishReason = FinishReason(rawValue: choice.finishReason ?? "stop") ?? .stop

        let usageInfo = usage.map {
            UsageInfo(
                promptTokens: $0.promptTokens,
                completionTokens: $0.completionTokens,
                totalTokens: $0.totalTokens
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

// Extension для конвертации Domain моделей в OpenAI формат
extension Message {
    func toOpenAIMessage() -> OpenAIMessage {
        OpenAIMessage(
            role: role.rawValue,
            content: content.isEmpty ? nil : content,
            toolCalls: toolCalls,
            toolCallId: toolCallId,
            name: role == .tool ? "tool_response" : nil
        )
    }
}
