//
//  OllamaProvider.swift
//  AI Advent Challenge
//
//  Created by Claude on 24.03.2026.
//

import Foundation

final class OllamaProvider: LLMProvider {
    let modelName: String
    let host: String
    let overrideTemperature: Double?
    let systemPromptOverride: String?
    private let networkClient: NetworkClient
    private let decoder = JSONDecoder()

    var supportsStreaming: Bool { true }

    init(modelName: String, networkClient: NetworkClient, host: String = "localhost", overrideTemperature: Double? = nil, systemPromptOverride: String? = nil) {
        self.modelName = modelName
        self.host = host
        self.networkClient = networkClient
        self.overrideTemperature = overrideTemperature
        self.systemPromptOverride = systemPromptOverride
    }

    private func applyOverrides(to messages: [LLMMessage]) -> [LLMMessage] {
        guard let override = systemPromptOverride else { return messages }
        return messages.map { msg in
            msg.role == .system ? LLMMessage(role: .system, content: override) : msg
        }
    }

    // MARK: - complete() — non-streaming

    func complete(
        messages: [LLMMessage],
        tools: [ToolDefinition]? = nil,
        temperature: Double = 0.7,
        maxTokens: Int? = nil,
        stop: [String]? = nil
    ) async throws -> AgentResponse {
        let request = OllamaRequest(
            model: modelName,
            messages: applyOverrides(to: messages).map { $0.toOpenAIMessage() },
            tools: tools,
            temperature: overrideTemperature ?? temperature,
            maxTokens: nil,  // локальная модель — без ограничений
            stop: stop,
            stream: false
        )

        let response: OllamaResponse = try await networkClient.request(
            endpoint: .ollamaChatCompletion(host: host),
            method: .post,
            body: request,
            headers: ["Content-Type": "application/json"]
        )
        return response.toAgentResponse()
    }

    // MARK: - streamComplete() — SSE streaming

    func streamComplete(
        messages: [LLMMessage],
        tools: [ToolDefinition]? = nil,
        temperature: Double = 0.7,
        maxTokens: Int? = nil,
        stop: [String]? = nil
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        let request = OllamaRequest(
            model: modelName,
            messages: applyOverrides(to: messages).map { $0.toOpenAIMessage() },
            tools: tools,
            temperature: overrideTemperature ?? temperature,
            maxTokens: nil,  // локальная модель — без ограничений
            stop: stop,
            stream: true
        )

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var finalUsage: UsageInfo?

                    let lineStream = self.networkClient.streamLines(
                        endpoint: .ollamaChatCompletion(host: host),
                        method: .post,
                        body: request,
                        headers: ["Content-Type": "application/json"]
                    )

                    for try await jsonString in lineStream {
                        guard let data = jsonString.data(using: .utf8),
                              let chunk = try? self.decoder.decode(OllamaStreamChunk.self, from: data)
                        else { continue }

                        let delta = chunk.choices.first?.delta

                        // Reasoning: Ollama шлёт дельту (каждый чанк — новая часть, не накопленная строка)
                        if let reasoning = delta?.reasoning, !reasoning.isEmpty {
                            continuation.yield(.thinking(reasoning))
                        }

                        // Content: дельта (обычно несколько токенов за раз)
                        if let content = delta?.content, !content.isEmpty {
                            continuation.yield(.content(content))
                        }

                        // Usage: в финальном чанке
                        if let usage = chunk.usage {
                            finalUsage = UsageInfo(
                                promptTokens: usage.promptTokens,
                                completionTokens: usage.completionTokens,
                                totalTokens: usage.totalTokens,
                                thoughtsTokens: nil
                            )
                        }
                    }

                    if let usage = finalUsage {
                        continuation.yield(.usage(usage))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
