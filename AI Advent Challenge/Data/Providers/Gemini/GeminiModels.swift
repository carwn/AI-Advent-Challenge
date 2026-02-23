//
//  GeminiModels.swift
//  AI Advent Challenge
//
//  Created by Claude on 22.02.2026.
//

import Foundation

// MARK: - Gemini Request

struct GeminiRequest: Encodable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiSystemInstruction?
    let tools: [GeminiTool]?
    let generationConfig: GeminiGenerationConfig?

    enum CodingKeys: String, CodingKey {
        case contents
        case systemInstruction = "system_instruction"
        case tools
        case generationConfig = "generation_config"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contents, forKey: .contents)
        try container.encodeIfPresent(systemInstruction, forKey: .systemInstruction)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encodeIfPresent(generationConfig, forKey: .generationConfig)
    }
}

struct GeminiContent: Encodable {
    let role: String
    let parts: [GeminiPart]
}

enum GeminiPart: Encodable {
    case text(String)
    case functionCall(name: String, args: [String: JSONValue])
    case functionResponse(name: String, response: [String: JSONValue])

    private struct FunctionCallData: Encodable {
        let name: String
        let args: [String: JSONValue]
    }

    private struct FunctionResponseData: Encodable {
        let name: String
        let response: [String: JSONValue]
    }

    enum CodingKeys: String, CodingKey {
        case text
        case functionCall
        case functionResponse
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t):
            try container.encode(t, forKey: .text)
        case .functionCall(let name, let args):
            try container.encode(FunctionCallData(name: name, args: args), forKey: .functionCall)
        case .functionResponse(let name, let response):
            try container.encode(FunctionResponseData(name: name, response: response), forKey: .functionResponse)
        }
    }
}

struct GeminiSystemInstruction: Encodable {
    let parts: [GeminiTextPart]
}

struct GeminiTextPart: Encodable {
    let text: String
}

struct GeminiGenerationConfig: Encodable {
    let temperature: Double?
    let maxOutputTokens: Int?
    let stopSequences: [String]?

    enum CodingKeys: String, CodingKey {
        case temperature
        case maxOutputTokens = "max_output_tokens"
        case stopSequences = "stop_sequences"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(maxOutputTokens, forKey: .maxOutputTokens)
        try container.encodeIfPresent(stopSequences, forKey: .stopSequences)
    }
}

struct GeminiTool: Encodable {
    let functionDeclarations: [GeminiFunctionDeclaration]

    enum CodingKeys: String, CodingKey {
        case functionDeclarations = "function_declarations"
    }
}

struct GeminiFunctionDeclaration: Encodable {
    let name: String
    let description: String
    let parameters: ToolDefinition.ParametersSchema
}

// MARK: - Gemini Response

struct GeminiResponse: Decodable {
    let candidates: [Candidate]
    let usageMetadata: UsageMetadata?

    struct Candidate: Decodable {
        let content: Content?
        let finishReason: String?
    }

    struct Content: Decodable {
        let parts: [Part]?
        let role: String?
    }

    struct Part: Decodable {
        let text: String?
        let functionCall: FunctionCall?

        struct FunctionCall: Decodable {
            let name: String
            let args: [String: JSONValue]
        }
    }

    struct UsageMetadata: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
        let totalTokenCount: Int?
        let thoughtsTokenCount: Int?
    }

    func toAgentResponse() -> AgentResponse {
        guard let content = candidates.first?.content else {
            return AgentResponse(
                message: Message(role: .assistant, content: ""),
                requiresToolExecution: false,
                finishReason: .stop,
                usage: nil
            )
        }

        let textContent = (content.parts ?? []).compactMap { $0.text }.joined()

        let functionCalls = (content.parts ?? []).compactMap { $0.functionCall }
        var toolCalls: [ToolCall]? = nil
        if !functionCalls.isEmpty {
            toolCalls = functionCalls.map { fc in
                let argsData = (try? JSONEncoder().encode(fc.args)) ?? Data()
                let argsString = String(data: argsData, encoding: .utf8) ?? "{}"
                return ToolCall(
                    id: UUID().uuidString,
                    type: "function",
                    function: ToolCall.FunctionCall(name: fc.name, arguments: argsString)
                )
            }
        }

        let requiresToolExecution = toolCalls != nil
        let finishReason: FinishReason = requiresToolExecution ? .toolCalls : .stop

        let message = Message(role: .assistant, content: textContent, toolCalls: toolCalls)

        let usageInfo = usageMetadata.map {
            UsageInfo(
                promptTokens: $0.promptTokenCount ?? 0,
                completionTokens: $0.candidatesTokenCount ?? 0,
                totalTokens: $0.totalTokenCount ?? 0,
                thoughtsTokens: $0.thoughtsTokenCount
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
