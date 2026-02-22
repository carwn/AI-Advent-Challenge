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
    private lazy var conversationRepository = ConversationRepository()

    // Domain Layer
    private lazy var toolExecutor: ToolExecutor = DefaultToolExecutor()

    // Presentation Layer
    lazy var messageHistoryStore = MessageHistoryStore()
    lazy var temperatureStore = TemperatureStore()
    let modelStore = ModelStore()

    private var cancellables = Set<AnyCancellable>()

    init() {
        // modelStore — вложенный ObservableObject; SwiftUI не подписывается
        // на него автоматически через @EnvironmentObject. Форвардим его изменения,
        // чтобы ContentView получал обновления и срабатывал .onChange(of: modelStore.selectedProvider).
        modelStore.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // Use Cases
    private func makeCreateAgentUseCase() -> CreateAgentUseCase {
        CreateAgentUseCase(
            providerFactory: providerFactory,
            toolExecutor: toolExecutor,
            temperatureStore: temperatureStore,
            modelStore: modelStore
        )
    }

    private func makeSendMessageUseCase(agent: Agent) -> SendMessageUseCase {
        SendMessageUseCase(
            agent: agent,
            repository: conversationRepository
        )
    }

    func setCustomAgentPrompt(_ prompt: String) {
        conversationRepository.setSystemPromptForAgent(.customPrompt, prompt: prompt)
    }

    // ViewModels
    func makeChatViewModel(conversation: Conversation) throws -> ChatViewModel {
        let agent = try makeCreateAgentUseCase().execute(agentType: conversation.agentType)
        let sendMessageUseCase = makeSendMessageUseCase(agent: agent)

        let setCustomPromptAction: ((String) -> Void)? = conversation.agentType == .promptCrafter
            ? { [weak self] prompt in self?.setCustomAgentPrompt(prompt) }
            : nil

        let conversationId = conversation.id
        let onTokensUpdated: (Int, Int) -> Void = { [weak self] prompt, completion in
            self?.conversationRepository.updateTokenUsage(
                id: conversationId,
                promptTokens: prompt,
                completionTokens: completion
            )
        }
        let onResponseTimeUpdated: (UUID, TimeInterval, String?) -> Void = { [weak self] messageId, responseTime, modelName in
            self?.conversationRepository.updateMessageResponseTime(
                conversationId: conversationId,
                messageId: messageId,
                responseTime: responseTime,
                modelName: modelName
            )
        }

        return ChatViewModel(
            sendMessageUseCase: sendMessageUseCase,
            conversation: conversation,
            historyStore: messageHistoryStore,
            temperatureStore: temperatureStore,
            setCustomPromptAction: setCustomPromptAction,
            onTokensUpdated: onTokensUpdated,
            onResponseTimeUpdated: onResponseTimeUpdated,
            currentModelName: { [weak self] in self?.modelStore.selectedProvider.displayName }
        )
    }

    func makeChatViewModel(agentType: AgentType) throws -> ChatViewModel {
        let conversation = conversationRepository.getOrCreateConversation(agentType: agentType)
        return try makeChatViewModel(conversation: conversation)
    }

    func makeAgentSelectionViewModel() -> AgentSelectionViewModel {
        AgentSelectionViewModel()
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(apiKeyManager: apiKeyManager)
    }
}
