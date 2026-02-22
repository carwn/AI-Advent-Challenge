//
//  AnthropicProvider.swift
//  AI Advent Challenge
//
//  Created by Claude on 22.02.2026.
//

import Foundation

final class AnthropicProvider: LLMProvider {
    let modelName: String
    private let networkClient: NetworkClient
    private let apiKey: String

    init(modelName: String = "claude-sonnet-4-6", networkClient: NetworkClient, apiKey: String) {
        self.modelName = modelName
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

        let anthropicMessages = convertMessages(nonSystemMessages)

        let anthropicTools: [AnthropicTool]? = {
            guard let tools, !tools.isEmpty else { return nil }
            return tools.map {
                AnthropicTool(
                    name: $0.function.name,
                    description: $0.function.description,
                    inputSchema: $0.function.parameters
                )
            }
        }()

        let request = AnthropicRequest(
            model: modelName,
            maxTokens: maxTokens ?? 1000,
            system: systemMessage,
            messages: anthropicMessages,
            tools: anthropicTools,
            temperature: temperature,
            stopSequences: stop
        )

        let response: AnthropicResponse = try await networkClient.request(
            endpoint: .anthropicMessages,
            method: .post,
            body: request,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json",
                "anthropic-version": "2023-06-01"
            ]
        )

        return response.toAgentResponse()
    }

    // MARK: - Message Conversion

    private func convertMessages(_ messages: [Message]) -> [AnthropicMessage] {
        var result: [AnthropicMessage] = []
        var i = 0

        while i < messages.count {
            let message = messages[i]

            switch message.role {
            case .tool:
                // Группируем последовательные tool-результаты в одно user-сообщение
                var toolBlocks: [AnthropicContentBlock] = []
                while i < messages.count && messages[i].role == .tool {
                    let toolMsg = messages[i]
                    toolBlocks.append(.toolResult(toolUseId: toolMsg.toolCallId, content: toolMsg.content))
                    i += 1
                }
                result.append(AnthropicMessage(role: "user", content: .blocks(toolBlocks)))

            case .assistant:
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    var blocks: [AnthropicContentBlock] = []
                    if !message.content.isEmpty {
                        blocks.append(.text(message.content))
                    }
                    for tc in toolCalls {
                        let inputData = Data(tc.function.arguments.utf8)
                        let input = (try? JSONDecoder().decode([String: JSONValue].self, from: inputData)) ?? [:]
                        blocks.append(.toolUse(id: tc.id, name: tc.function.name, input: input))
                    }
                    result.append(AnthropicMessage(role: "assistant", content: .blocks(blocks)))
                } else {
                    result.append(AnthropicMessage(role: "assistant", content: .text(message.content)))
                }
                i += 1

            case .user:
                result.append(AnthropicMessage(role: "user", content: .text(message.content)))
                i += 1

            case .system:
                i += 1
            }
        }

        return result
    }
}
