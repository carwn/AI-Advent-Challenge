//
//  GeminiProvider.swift
//  AI Advent Challenge
//
//  Created by Claude on 22.02.2026.
//

import Foundation

final class GeminiProvider: LLMProvider {
    let modelName: String = "gemini-3-flash-preview"
    private let networkClient: NetworkClient
    private let apiKey: String

    init(networkClient: NetworkClient, apiKey: String) {
        self.networkClient = networkClient
        self.apiKey = apiKey
    }

    func complete(
        messages: [Message],
        tools: [ToolDefinition]? = nil,
        temperature: Double = 0.7,
        maxTokens: Int? = nil,
        stop: [String]? = nil
    ) async throws -> AgentResponse {
        let systemMessage = messages.first { $0.role == .system }?.content
        let nonSystemMessages = messages.filter { $0.role != .system }

        let systemInstruction = systemMessage.map {
            GeminiSystemInstruction(parts: [GeminiTextPart(text: $0)])
        }

        let contents = convertMessages(nonSystemMessages)

        let geminiTools: [GeminiTool]? = {
            guard let tools, !tools.isEmpty else { return nil }
            let declarations = tools.map {
                GeminiFunctionDeclaration(
                    name: $0.function.name,
                    description: $0.function.description,
                    parameters: $0.function.parameters
                )
            }
            return [GeminiTool(functionDeclarations: declarations)]
        }()

        let config = GeminiGenerationConfig(
            temperature: temperature,
            maxOutputTokens: maxTokens,
            stopSequences: (stop?.isEmpty == false) ? stop : nil
        )

        let request = GeminiRequest(
            contents: contents,
            systemInstruction: systemInstruction,
            tools: geminiTools,
            generationConfig: config
        )

        let response: GeminiResponse = try await networkClient.request(
            endpoint: .geminiGenerateContent(model: modelName),
            method: .post,
            body: request,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ]
        )

        return response.toAgentResponse()
    }

    // MARK: - Message Conversion

    private func convertMessages(_ messages: [Message]) -> [GeminiContent] {
        // Маппинг toolCallId → имя функции для tool-результатов
        var toolCallIdToName: [String: String] = [:]
        for message in messages where message.role == .assistant {
            for tc in message.toolCalls ?? [] {
                toolCallIdToName[tc.id] = tc.function.name
            }
        }

        var result: [GeminiContent] = []
        var i = 0

        while i < messages.count {
            let message = messages[i]

            switch message.role {
            case .user:
                result.append(GeminiContent(role: "user", parts: [.text(message.content)]))
                i += 1

            case .assistant:
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    var parts: [GeminiPart] = []
                    if !message.content.isEmpty {
                        parts.append(.text(message.content))
                    }
                    for tc in toolCalls {
                        let inputData = Data(tc.function.arguments.utf8)
                        let args = (try? JSONDecoder().decode([String: JSONValue].self, from: inputData)) ?? [:]
                        parts.append(.functionCall(name: tc.function.name, args: args))
                    }
                    result.append(GeminiContent(role: "model", parts: parts))
                } else {
                    result.append(GeminiContent(role: "model", parts: [.text(message.content)]))
                }
                i += 1

            case .tool:
                // Группируем последовательные tool-результаты в одно сообщение
                var parts: [GeminiPart] = []
                while i < messages.count && messages[i].role == .tool {
                    let toolMsg = messages[i]
                    let funcName = toolCallIdToName[toolMsg.toolCallId ?? ""] ?? "unknown"
                    parts.append(.functionResponse(
                        name: funcName,
                        response: ["result": .string(toolMsg.content)]
                    ))
                    i += 1
                }
                result.append(GeminiContent(role: "user", parts: parts))

            case .system:
                i += 1
            }
        }

        return result
    }
}
