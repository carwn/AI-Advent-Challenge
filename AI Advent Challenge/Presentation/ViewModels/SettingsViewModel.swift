//
//  SettingsViewModel.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var openAIKey: String = ""
    @Published var showingSaveSuccess: Bool = false
    @Published var error: String?

    private let apiKeyManager: APIKeyManager

    init(apiKeyManager: APIKeyManager) {
        self.apiKeyManager = apiKeyManager
        loadAPIKey()
    }

    func loadAPIKey() {
        do {
            if let key = try apiKeyManager.getAPIKey(for: .openAI) {
                openAIKey = key
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func saveAPIKey() {
        guard !openAIKey.isEmpty else {
            error = "API key cannot be empty"
            return
        }

        do {
            try apiKeyManager.setAPIKey(openAIKey, for: .openAI)
            showingSaveSuccess = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteAPIKey() {
        do {
            try apiKeyManager.deleteAPIKey(for: .openAI)
            openAIKey = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
