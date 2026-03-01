//
//  OpenAIProvider.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

final class OpenAIProvider: LLMProvider {
    let modelName: String
    private let networkClient: NetworkClient
    private let apiKey: String

    // Модели, использующие max_completion_tokens вместо max_tokens
    private static let maxCompletionTokensModels: Set<String> = ["gpt-5.2"]

    init(
        modelName: String = "gpt-4.1-mini",
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
        let usesNewParam = Self.maxCompletionTokensModels.contains(modelName)
        let request = OpenAIRequest(
            model: modelName,
            messages: messages.map { $0.toOpenAIMessage() },
            tools: tools,
            temperature: temperature,
            maxTokens: usesNewParam ? nil : maxTokens,
            maxCompletionTokens: usesNewParam ? maxTokens : nil,
            stop: stop
        )

        let endpoint = APIEndpoint.openAIChatCompletion
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
