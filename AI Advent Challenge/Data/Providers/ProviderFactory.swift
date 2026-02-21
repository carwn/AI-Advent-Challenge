//
//  ProviderFactory.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

enum ProviderType: String, CaseIterable {
    case openAI = "gpt-4.1-mini"
    case openAIGPT52 = "gpt-5.2"
    case gemini = "gemini-3-flash-preview"
    case anthropic = "claude-sonnet-4-6"

    var displayName: String {
        switch self {
        case .openAI: return "GPT-4.1 Mini"
        case .openAIGPT52: return "GPT-5.2"
        case .gemini: return "Gemini 3 Flash Preview"
        case .anthropic: return "Claude Sonnet 4.6"
        }
    }
}

final class ProviderFactory {
    private let networkClient: NetworkClient
    private let apiKeyManager: APIKeyManager

    init(networkClient: NetworkClient, apiKeyManager: APIKeyManager) {
        self.networkClient = networkClient
        self.apiKeyManager = apiKeyManager
    }

    func createProvider(_ type: ProviderType) throws -> LLMProvider {
        guard let apiKey = try apiKeyManager.getAPIKey(for: .openAI) else {
            throw ProviderError.missingAPIKey("API key not found. Please add it in Settings.")
        }
        switch type {
        case .openAI:
            return OpenAIProvider(modelName: "gpt-4.1-mini", networkClient: networkClient, apiKey: apiKey)
        case .openAIGPT52:
            return OpenAIProvider(modelName: "gpt-5.2", networkClient: networkClient, apiKey: apiKey)
        case .gemini:
            return GeminiProvider(networkClient: networkClient, apiKey: apiKey)
        case .anthropic:
            return AnthropicProvider(networkClient: networkClient, apiKey: apiKey)
        }
    }
}

enum ProviderError: LocalizedError {
    case missingAPIKey(String)
    case unsupportedProvider

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let message):
            return message
        case .unsupportedProvider:
            return "Provider type is not supported"
        }
    }
}
