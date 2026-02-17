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

    // Use Cases
    private func makeCreateAgentUseCase() -> CreateAgentUseCase {
        CreateAgentUseCase(
            providerFactory: providerFactory,
            toolExecutor: toolExecutor
        )
    }

    private func makeSendMessageUseCase(agent: Agent) -> SendMessageUseCase {
        SendMessageUseCase(
            agent: agent,
            repository: conversationRepository
        )
    }

    // ViewModels
    func makeChatViewModel(conversation: Conversation) throws -> ChatViewModel {
        let agent = try makeCreateAgentUseCase().execute(agentType: conversation.agentType)
        let sendMessageUseCase = makeSendMessageUseCase(agent: agent)

        return ChatViewModel(
            sendMessageUseCase: sendMessageUseCase,
            conversation: conversation
        )
    }

    func makeAgentSelectionViewModel() -> AgentSelectionViewModel {
        AgentSelectionViewModel(
            createAgentUseCase: makeCreateAgentUseCase(),
            conversationRepository: conversationRepository
        )
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(apiKeyManager: apiKeyManager)
    }
}
