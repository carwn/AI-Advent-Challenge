//
//  ProviderFactory.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

enum ProviderType: String, CaseIterable {
    case gpt41Nano = "gpt-4.1-nano"
    case gpt41Mini = "gpt-4.1-mini"
    case gpt41 = "gpt-4.1"
    case claudeHaiku = "claude-haiku-4-5"
    case claudeSonnet4 = "claude-sonnet-4-5"
    case claudeOpus45 = "claude-opus-4-5"
    case geminiFlashLite = "gemini-2.5-flash-lite"
    case geminiFlash = "gemini-2.5-flash"
    case geminiPro = "gemini-2.5-pro"

    var displayName: String {
        switch self {
        case .gpt41Mini: return "GPT-4.1 Mini"
        case .gpt41Nano: return "GPT-4.1 Nano"
        case .gpt41: return "GPT-4.1"
        case .geminiFlashLite: return "Gemini 2.5 Flash Lite"
        case .geminiFlash: return "Gemini 2.5 Flash"
        case .geminiPro: return "Gemini 2.5 Pro"
        case .claudeHaiku: return "Claude Haiku 4.5"
        case .claudeSonnet4: return "Claude Sonnet 4.5"
        case .claudeOpus45: return "Claude Opus 4.5"
        }
    }

    /// Цены в рублях за 1 млн токенов (proxyapi.ru, с НДС 5%)
    var pricingRUB: (input: Double, output: Double) {
        switch self {
        case .gpt41Nano:       return (26,   104)
        case .gpt41Mini:       return (104,  413)
        case .gpt41:           return (516,  2062)
        case .claudeHaiku:     return (295,  1474)
        case .claudeSonnet4:   return (774,  3866)
        case .claudeOpus45:    return (1516, 7579)
        case .geminiFlashLite: return (26,   129)
        case .geminiFlash:     return (78,   645)
        case .geminiPro:       return (323,  2577)
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
        case .gpt41Mini:
            return OpenAIProvider(modelName: "gpt-4.1-mini", networkClient: networkClient, apiKey: apiKey)
        case .gpt41Nano:
            return OpenAIProvider(modelName: "gpt-4.1-nano", networkClient: networkClient, apiKey: apiKey)
        case .gpt41:
            return OpenAIProvider(modelName: "gpt-4.1", networkClient: networkClient, apiKey: apiKey)
        case .geminiFlashLite:
            return GeminiProvider(modelName: "gemini-2.5-flash-lite", networkClient: networkClient, apiKey: apiKey)
        case .geminiFlash:
            return GeminiProvider(modelName: "gemini-2.5-flash", networkClient: networkClient, apiKey: apiKey)
        case .geminiPro:
            return GeminiProvider(modelName: "gemini-2.5-pro", networkClient: networkClient, apiKey: apiKey)
        case .claudeHaiku:
            return AnthropicProvider(modelName: "claude-haiku-4-5", networkClient: networkClient, apiKey: apiKey)
        case .claudeSonnet4:
            return AnthropicProvider(modelName: "claude-sonnet-4-5", networkClient: networkClient, apiKey: apiKey)
        case .claudeOpus45:
            return AnthropicProvider(modelName: "claude-opus-4-5", networkClient: networkClient, apiKey: apiKey)
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
