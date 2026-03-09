//
//  APIKeyManager.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

enum APIKeyProvider {
    case openAI
    case tavily

    var serviceName: String {
        switch self {
        case .openAI:
            return "com.aiapp.openai"
        case .tavily:
            return "com.aiapp.tavily"
        }
    }
}

final class APIKeyManager {
    private let keychainService: KeychainService

    init(keychainService: KeychainService) {
        self.keychainService = keychainService
    }

    func getAPIKey(for provider: APIKeyProvider) throws -> String? {
        return try keychainService.get(service: provider.serviceName)
    }

    func setAPIKey(_ key: String, for provider: APIKeyProvider) throws {
        try keychainService.save(key, service: provider.serviceName)
    }

    func deleteAPIKey(for provider: APIKeyProvider) throws {
        try keychainService.delete(service: provider.serviceName)
    }
}
