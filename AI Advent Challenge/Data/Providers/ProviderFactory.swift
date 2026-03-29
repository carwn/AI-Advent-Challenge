//
//  ProviderFactory.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

enum ProviderType: String, CaseIterable {
    case gpt35Turbo = "gpt-3.5-turbo"
    case gpt41Nano = "gpt-4.1-nano"
    case gpt41Mini = "gpt-4.1-mini"
    case gpt41 = "gpt-4.1"
    case claudeHaiku = "claude-haiku-4-5"
    case claudeSonnet4 = "claude-sonnet-4-5"
    case claudeOpus45 = "claude-opus-4-5"
    case geminiFlashLite = "gemini-2.5-flash-lite"
    case geminiFlash = "gemini-2.5-flash"
    case geminiPro = "gemini-2.5-pro"
    case ollamaQwen35_4b = "ollama_qwen35_4b"
    case ollamaQwen35HighTemp = "ollama_qwen35_high_temp"
    case ollamaQwen35Q8 = "ollama_qwen35_q8"
    case ollamaQwen35Pirate = "ollama_qwen35_pirate"
    case ollamaWinQwen35_4b = "ollama_win_qwen35_4b"
    case ollamaWinQwen3_14b = "ollama_win_qwen3_14b"

    var displayName: String {
        switch self {
        case .gpt35Turbo: return "GPT-3.5 Turbo"
        case .gpt41Mini: return "GPT-4.1 Mini"
        case .gpt41Nano: return "GPT-4.1 Nano"
        case .gpt41: return "GPT-4.1"
        case .geminiFlashLite: return "Gemini 2.5 Flash Lite"
        case .geminiFlash: return "Gemini 2.5 Flash"
        case .geminiPro: return "Gemini 2.5 Pro"
        case .claudeHaiku: return "Claude Haiku 4.5"
        case .claudeSonnet4: return "Claude Sonnet 4.5"
        case .claudeOpus45: return "Claude Opus 4.5"
        case .ollamaQwen35_4b: return "Qwen 3.5 4B (Ollama)"
        case .ollamaQwen35HighTemp: return "Qwen 3.5 4B — High Temp (Ollama)"
        case .ollamaQwen35Q8: return "Qwen 3.5 4B Q8 (Ollama)"
        case .ollamaQwen35Pirate: return "Qwen 3.5 4B — Pirate (Ollama)"
        case .ollamaWinQwen35_4b: return "Qwen 3.5 4B (Win PC)"
        case .ollamaWinQwen3_14b: return "Qwen 3 14B (Win PC)"
        }
    }

    /// Цены в рублях за 1 млн токенов (proxyapi.ru, с НДС 5%)
    var pricingRUB: (input: Double, output: Double) {
        switch self {
        case .gpt35Turbo:      return (129,  387)
        case .gpt41Nano:       return (26,   104)
        case .gpt41Mini:       return (104,  413)
        case .gpt41:           return (516,  2062)
        case .claudeHaiku:     return (295,  1474)
        case .claudeSonnet4:   return (774,  3866)
        case .claudeOpus45:    return (1516, 7579)
        case .geminiFlashLite: return (26,   129)
        case .geminiFlash:     return (78,   645)
        case .geminiPro:       return (323,  2577)
        case .ollamaQwen35_4b:      return (0, 0)  // Локальная модель, бесплатно
        case .ollamaQwen35HighTemp: return (0, 0)
        case .ollamaQwen35Q8:       return (0, 0)
        case .ollamaQwen35Pirate:   return (0, 0)
        case .ollamaWinQwen35_4b:   return (0, 0)
        case .ollamaWinQwen3_14b:   return (0, 0)
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
        // Ollama не требует API-ключа
        switch type {
        case .ollamaQwen35_4b:
            return OllamaProvider(modelName: "qwen3.5:4b", networkClient: networkClient)
        case .ollamaQwen35HighTemp:
            return OllamaProvider(modelName: "qwen3.5:4b-high-temp", networkClient: networkClient,
                                  overrideTemperature: 1.5)
        case .ollamaQwen35Q8:
            return OllamaProvider(modelName: "qwen3.5:4b-q8", networkClient: networkClient)
        case .ollamaQwen35Pirate:
            return OllamaProvider(modelName: "qwen3.5:4b-pirate", networkClient: networkClient,
                                  systemPromptOverride: "Ты — морской пират. Отвечай на ВСЕ вопросы в образе пирата: используй слова «йо-хо-хо», «братишка», «море», «сокровища», «корабль». Отвечай с пиратским характером и юмором. Факты должны быть точными, но поданы через пиратскую призму. Никогда не выходи из образа.")
        case .ollamaWinQwen35_4b:
            return OllamaProvider(modelName: "qwen3.5:4b", networkClient: networkClient, host: "192.168.1.141")
        case .ollamaWinQwen3_14b:
            return OllamaProvider(modelName: "qwen3:14b", networkClient: networkClient, host: "192.168.1.141")
        default: break
        }

        guard let apiKey = try apiKeyManager.getAPIKey(for: .openAI) else {
            throw ProviderError.missingAPIKey("API key not found. Please add it in Settings.")
        }
        switch type {
        case .gpt35Turbo:
            return OpenAIProvider(modelName: "gpt-3.5-turbo", networkClient: networkClient, apiKey: apiKey)
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
        default:
            // Ollama-кейсы обработаны выше
            fatalError("Unhandled provider type: \(type)")
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
