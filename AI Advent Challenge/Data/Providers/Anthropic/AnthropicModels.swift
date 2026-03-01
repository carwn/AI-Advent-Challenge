//
//  AnthropicModels.swift
//  AI Advent Challenge
//
//  Created by Claude on 22.02.2026.
//

import Foundation

// MARK: - JSONValue для произвольного JSON

enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode JSONValue"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}

// MARK: - Anthropic Request

struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [AnthropicMessage]
    let tools: [AnthropicTool]?
    let temperature: Double?
    let stopSequences: [String]?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case tools
        case temperature
        case stopSequences = "stop_sequences"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(system, forKey: .system)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(stopSequences, forKey: .stopSequences)
    }
}

struct AnthropicTool: Encodable {
    let name: String
    let description: String
    let inputSchema: ToolDefinition.ParametersSchema

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

struct AnthropicMessage: Encodable {
    let role: String
    let content: AnthropicMessageContent
}

enum AnthropicMessageContent: Encodable {
    case text(String)
    case blocks([AnthropicContentBlock])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let s): try container.encode(s)
        case .blocks(let blocks): try container.encode(blocks)
        }
    }
}

enum AnthropicContentBlock: Encodable {
    case text(String)
    case toolUse(id: String, name: String, input: [String: JSONValue])
    case toolResult(toolUseId: String?, content: String?)

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case toolUseId = "tool_use_id"
        case content
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let content):
            try container.encode("tool_result", forKey: .type)
            try container.encodeIfPresent(toolUseId, forKey: .toolUseId)
            try container.encodeIfPresent(content, forKey: .content)
        }
    }
}

// MARK: - Anthropic Response

struct AnthropicResponse: Decodable {
    let id: String
    let type: String
    let role: String
    let content: [AnthropicResponseBlock]
    let model: String
    let stopReason: String?
    let usage: AnthropicUsage?

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model
        case stopReason = "stop_reason"
        case usage
    }

    struct AnthropicResponseBlock: Decodable {
        let type: String
        let text: String?
        let id: String?
        let name: String?
        let input: [String: JSONValue]?
    }

    struct AnthropicUsage: Decodable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    func toAgentResponse() -> AgentResponse {
        let textContent = content
            .filter { $0.type == "text" }
            .compactMap { $0.text }
            .joined()

        let toolUseBlocks = content.filter { $0.type == "tool_use" }
        var toolCalls: [ToolCall]? = nil
        if !toolUseBlocks.isEmpty {
            let calls = toolUseBlocks.compactMap { block -> ToolCall? in
                guard let id = block.id, let name = block.name, let input = block.input else { return nil }
                let argsData = (try? JSONEncoder().encode(input)) ?? Data()
                let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                return ToolCall(id: id, type: "function", function: ToolCall.FunctionCall(name: name, arguments: argsString))
            }
            if !calls.isEmpty { toolCalls = calls }
        }

        let requiresToolExecution = stopReason == "tool_use"
        let finishReason: FinishReason = stopReason == "tool_use" ? .toolCalls : .stop

        let message = LLMResponse(
            content: textContent,
            toolCalls: toolCalls
        )

        let usageInfo = usage.map {
            UsageInfo(
                promptTokens: $0.inputTokens,
                completionTokens: $0.outputTokens,
                totalTokens: $0.inputTokens + $0.outputTokens,
                thoughtsTokens: nil
            )
        }

        return AgentResponse(
            message: message,
            requiresToolExecution: requiresToolExecution,
            finishReason: finishReason,
            usage: usageInfo
        )
    }
}
