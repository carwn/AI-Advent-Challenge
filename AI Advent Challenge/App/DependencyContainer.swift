//
//  DependencyContainer.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class DependencyContainer: ObservableObject {
    // Infrastructure
    private lazy var keychainService = KeychainService()
    private lazy var apiKeyManager = APIKeyManager(keychainService: keychainService)
    private lazy var networkLogger: NetworkLogger = OSNetworkLogger()
    private lazy var networkClient = NetworkClient(logger: networkLogger)

    // Data Layer
    private lazy var providerFactory = ProviderFactory(
        networkClient: networkClient,
        apiKeyManager: apiKeyManager
    )

    // Domain Layer
    private lazy var toolExecutor: ToolExecutor = DefaultToolExecutor()

    // Presentation Layer
    lazy var messageHistoryStore = MessageHistoryStore()
    let modelStore = ModelStore()

    private var _agents: [any Agent]?
    private var cancellables = Set<AnyCancellable>()

    init() {
        modelStore.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
                self?._agents = nil
            }
            .store(in: &cancellables)
    }

    func makeAgents() throws -> [any Agent] {
        if let cached = _agents { return cached }
        let provider = try providerFactory.createProvider(modelStore.selectedProvider)
        let useCase = SendMessageUseCase(provider: provider, toolExecutor: toolExecutor)
        let agents: [any Agent] = [
            GeneralAgent(sendMessage: useCase),
            WeatherAgent(sendMessage: useCase),
            WeatherJSONAgent(sendMessage: useCase),
            BulletListAgent(sendMessage: useCase),
            Stop13Agent(sendMessage: useCase),
            StepByStepAgent(sendMessage: useCase),
            PromptCrafterAgent(sendMessage: useCase),
            MultiExpertAgent(sendMessage: useCase),
        ]
        _agents = agents
        return agents
    }

    func makeChatViewModel(agent: any Agent) -> ChatViewModel {
        ChatViewModel(agent: agent, historyStore: messageHistoryStore)
    }

    func makeAgentSelectionViewModel() -> AgentSelectionViewModel {
        AgentSelectionViewModel(agents: (try? makeAgents()) ?? [])
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(apiKeyManager: apiKeyManager)
    }
}
