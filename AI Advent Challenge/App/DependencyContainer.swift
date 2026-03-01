//
//  DependencyContainer.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation
import SwiftUI
import Combine

struct AgentTemplate: Identifiable {
    let id: String   // agentKey
    let name: String
    let icon: String
    let description: String
    let compressionPolicyDescription: String?
}

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
    lazy var conversationPersistence = ConversationPersistenceService()
    lazy var branchConversation: any BranchConversationUseCase =
        BranchConversationInteractor(persistence: conversationPersistence)

    // Presentation Layer
    lazy var messageHistoryStore = MessageHistoryStore()
    let modelStore = ModelStore()

    private var cancellables = Set<AnyCancellable>()

    init() {
        modelStore.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Agent templates

    var agentTemplates: [AgentTemplate] {
        [
            AgentTemplate(id: "general_agent",
                          name: "Универсальный ассистент",
                          icon: "brain",
                          description: "Универсальный помощник для любых задач",
                          compressionPolicyDescription: nil),
            AgentTemplate(id: "weather_agent",
                          name: "Агент погоды",
                          icon: "cloud.sun",
                          description: "Информация о погоде в любом месте",
                          compressionPolicyDescription: nil),
            AgentTemplate(id: "weather_json_agent",
                          name: "Агент погоды (JSON)",
                          icon: "cloud.sun.fill",
                          description: "Погода в виде JSON-объекта",
                          compressionPolicyDescription: nil),
            AgentTemplate(id: "context_managed_agent",
                          name: "Агент с памятью",
                          icon: "memorychip",
                          description: "Summary-сжатие при >1500 токенов",
                          compressionPolicyDescription: "Summary при >1500 токенов"),
            AgentTemplate(id: "sliding_window_agent",
                          name: "Агент скользящего окна",
                          icon: "rectangle.3.offgrid",
                          description: "Последние 5 сообщений в API",
                          compressionPolicyDescription: "Последние 5 сообщений"),
            AgentTemplate(id: "sticky_facts_agent",
                          name: "Агент с фактами",
                          icon: "tag.fill",
                          description: "Факты + последние 10 сообщений в API",
                          compressionPolicyDescription: "Факты + последние 10 сообщений"),
        ]
    }

    // MARK: - Factory methods

    func makeAgent(record: ConversationRecord) throws -> any Agent {
        let provider = try providerFactory.createProvider(modelStore.selectedProvider)
        let useCase = SendMessageToLMMInteractor(provider: provider, toolExecutor: toolExecutor)
        let id = record.id
        switch record.agentKey {
        case "general_agent":
            return GeneralAgent(sendMessage: useCase, persistence: conversationPersistence, conversationId: id)
        case "weather_agent":
            return WeatherAgent(sendMessage: useCase, persistence: conversationPersistence, conversationId: id)
        case "weather_json_agent":
            return WeatherJSONAgent(sendMessage: useCase, persistence: conversationPersistence, conversationId: id)
        case "context_managed_agent":
            return ContextManagedAgent(
                sendMessage: useCase,
                persistence: conversationPersistence,
                conversationId: id,
                compressionPolicy: SummaryContextCompressionPolicy(
                    sendMessage: useCase,
                    persistenceKey: id.uuidString
                )
            )
        case "sliding_window_agent":
            return SlidingWindowAgent(
                sendMessage: useCase,
                persistence: conversationPersistence,
                conversationId: id,
                compressionPolicy: SlidingWindowContextCompressionPolicy(windowSize: 5)
            )
        case "sticky_facts_agent":
            return StickyFactsAgent(
                sendMessage: useCase,
                persistence: conversationPersistence,
                conversationId: id,
                compressionPolicy: StickyFactsCompressionPolicy(
                    sendMessage: useCase,
                    windowSize: 5,
                    persistenceKey: id.uuidString
                )
            )
        default:
            return GeneralAgent(sendMessage: useCase, persistence: conversationPersistence, conversationId: id)
        }
    }

    func createConversation(agentKey: String) -> ConversationRecord? {
        guard let template = agentTemplates.first(where: { $0.id == agentKey }) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, HH:mm"
        formatter.locale = Locale(identifier: "ru_RU")
        let record = ConversationRecord(
            id: UUID(),
            agentKey: template.id,
            agentName: template.name,
            agentIcon: template.icon,
            title: formatter.string(from: Date()),
            lastMessagePreview: nil,
            lastMessageDate: nil,
            createdAt: Date()
        )
        conversationPersistence.saveRecord(record)
        return record
    }

    func makeChatViewModel(agent: any Agent) -> ChatViewModel {
        ChatViewModel(agent: agent, historyStore: messageHistoryStore)
    }

    func makeAgentSelectionViewModel() -> AgentSelectionViewModel {
        AgentSelectionViewModel(templates: agentTemplates)
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        SettingsViewModel(apiKeyManager: apiKeyManager)
    }
}
