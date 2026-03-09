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
    @Published var tavilyKey: String = ""
    @Published var showingSaveSuccess: Bool = false
    @Published var showingMemorySaveSuccess: Bool = false
    @Published var showingTavilySaveSuccess: Bool = false
    @Published var error: String?

    private let apiKeyManager: APIKeyManager
    private let persistence: ConversationPersistenceService
    let longTermMemoryStore: LongTermMemoryStore

    init(apiKeyManager: APIKeyManager, longTermMemoryStore: LongTermMemoryStore, persistence: ConversationPersistenceService) {
        self.apiKeyManager = apiKeyManager
        self.longTermMemoryStore = longTermMemoryStore
        self.persistence = persistence
        loadAPIKey()
        loadTavilyKey()
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

    func loadTavilyKey() {
        do {
            if let key = try apiKeyManager.getAPIKey(for: .tavily) {
                tavilyKey = key
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func saveTavilyKey() {
        guard !tavilyKey.isEmpty else { return }
        do {
            try apiKeyManager.setAPIKey(tavilyKey, for: .tavily)
            showingTavilySaveSuccess = true
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteTavilyKey() {
        do {
            try apiKeyManager.deleteAPIKey(for: .tavily)
            tavilyKey = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func saveLongTermMemory() {
        longTermMemoryStore.save()
        showingMemorySaveSuccess = true
    }

    func clearAllData() {
        persistence.deleteAllData()
        longTermMemoryStore.text = ""
    }
}
