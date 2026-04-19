//
//  DeepSeekProvider.swift
//  AI Advent Challenge
//
//  DeepSeek uses OpenAI-compatible API format via ProxyAPI.ru.
//  Reuses OpenAI request/response types directly.
//

import Foundation

final class DeepSeekProvider: LLMProvider {
    let modelName: String
    private let networkClient: NetworkClient
    private let apiKey: String

    init(
        modelName: String = "deepseek-chat",
        networkClient: NetworkClient,
        apiKey: String
    ) {
        self.modelName = modelName
        self.networkClient = networkClient
        self.apiKey = apiKey
    }

    func complete(
        messages: [LLMMessage],
        tools: [ToolDefinition]? = nil,
        temperature: Double = 0.7,
        maxTokens: Int? = nil,
        stop: [String]? = nil
    ) async throws -> AgentResponse {
        let request = OpenAIRequest(
            model: modelName,
            messages: messages.map { $0.toOpenAIMessage() },
            tools: tools,
            temperature: temperature,
            maxTokens: maxTokens,
            maxCompletionTokens: nil,
            stop: stop
        )

        let endpoint = APIEndpoint.deepSeekChatCompletion
        let response: OpenAIResponse = try await networkClient.request(
            endpoint: endpoint,
            method: .post,
            body: request,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ]
        )

        return response.toAgentResponse()
    }
}
