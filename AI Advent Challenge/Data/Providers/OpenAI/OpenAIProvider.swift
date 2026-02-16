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

    init(
        modelName: String = "gpt-4-turbo-preview",
        networkClient: NetworkClient,
        apiKey: String
    ) {
        self.modelName = modelName
        self.networkClient = networkClient
        self.apiKey = apiKey
    }

    func complete(
        messages: [Message],
        tools: [ToolDefinition]? = nil,
        temperature: Double = 0.7,
        maxTokens: Int? = nil
    ) async throws -> AgentResponse {
        let request = OpenAIRequest(
            model: modelName,
            messages: messages.map { $0.toOpenAIMessage() },
            tools: tools,
            temperature: temperature,
            maxTokens: maxTokens
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
