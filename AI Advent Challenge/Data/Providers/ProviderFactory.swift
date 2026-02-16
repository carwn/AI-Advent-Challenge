//
//  ProviderFactory.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

enum ProviderType {
    case openAI
}

final class ProviderFactory {
    private let networkClient: NetworkClient
    private let apiKeyManager: APIKeyManager

    init(networkClient: NetworkClient, apiKeyManager: APIKeyManager) {
        self.networkClient = networkClient
        self.apiKeyManager = apiKeyManager
    }

    func createProvider(_ type: ProviderType) throws -> LLMProvider {
        switch type {
        case .openAI:
            guard let apiKey = try apiKeyManager.getAPIKey(for: .openAI) else {
                throw ProviderError.missingAPIKey("OpenAI API key not found. Please add it in Settings.")
            }
            return OpenAIProvider(
                networkClient: networkClient,
                apiKey: apiKey
            )
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
