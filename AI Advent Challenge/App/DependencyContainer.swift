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
    lazy var longTermMemoryStore = LongTermMemoryStore(agentKey: "triple_memory_agent")

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
                          description: "Summary-сжатие при >\(SummaryContextCompressionPolicy.defaultTriggerTokens) токенов",
                          compressionPolicyDescription: "Summary при >\(SummaryContextCompressionPolicy.defaultTriggerTokens) токенов"),
            AgentTemplate(id: "sliding_window_agent",
                          name: "Агент скользящего окна",
                          icon: "rectangle.3.offgrid",
                          description: "Последние \(SlidingWindowContextCompressionPolicy.defaultWindowSize) сообщений в API",
                          compressionPolicyDescription: "Последние \(SlidingWindowContextCompressionPolicy.defaultWindowSize) сообщений"),
            AgentTemplate(id: "sticky_facts_agent",
                          name: "Агент с фактами",
                          icon: "tag.fill",
                          description: "Факты + последние \(StickyFactsCompressionPolicy.defaultWindowSize) сообщений в API",
                          compressionPolicyDescription: "Факты + последние \(StickyFactsCompressionPolicy.defaultWindowSize) сообщений"),
            AgentTemplate(id: "triple_memory_agent",
                          name: "Агент с тройной памятью",
                          icon: "brain.filled.head.profile",
                          description: "Долговременная (Settings) + рабочая + последние \(TripleMemoryCompressionPolicy.defaultWindowSize) сообщений",
                          compressionPolicyDescription: "3 уровня памяти (долгосрочная + рабочая + окно)"),
            AgentTemplate(id: "user_profile_agent",
                          name: "Профайлер",
                          icon: "person.text.rectangle.fill",
                          description: "Собирает профиль предпочтений и сохраняет в долговременную память",
                          compressionPolicyDescription: nil),
            AgentTemplate(id: "task_state_machine_agent",
                          name: "Менеджер задач",
                          icon: "checklist",
                          description: "Ведёт задачи через фазы: планирование → выполнение → валидация → готово. Поддерживает паузу.",
                          compressionPolicyDescription: nil),
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
                    summaryTriggerTokens: SummaryContextCompressionPolicy.defaultTriggerTokens,
                    persistenceKey: id.uuidString
                )
            )
        case "sliding_window_agent":
            return SlidingWindowAgent(
                sendMessage: useCase,
                persistence: conversationPersistence,
                conversationId: id,
                compressionPolicy: SlidingWindowContextCompressionPolicy(
                    windowSize: SlidingWindowContextCompressionPolicy.defaultWindowSize
                )
            )
        case "sticky_facts_agent":
            return StickyFactsAgent(
                sendMessage: useCase,
                persistence: conversationPersistence,
                conversationId: id,
                compressionPolicy: StickyFactsCompressionPolicy(
                    sendMessage: useCase,
                    windowSize: StickyFactsCompressionPolicy.defaultWindowSize,
                    persistenceKey: id.uuidString
                )
            )
        case "triple_memory_agent":
            return TripleMemoryAgent(
                sendMessage: useCase,
                persistence: conversationPersistence,
                conversationId: id,
                compressionPolicy: TripleMemoryCompressionPolicy(
                    sendMessage: useCase,
                    windowSize: TripleMemoryCompressionPolicy.defaultWindowSize,
                    persistenceKey: id.uuidString,
                    longTermMemory: longTermMemoryStore
                )
            )
        case "user_profile_agent":
            return UserProfileAgent(
                sendMessage: useCase,
                persistence: conversationPersistence,
                conversationId: id,
                longTermMemoryStore: longTermMemoryStore
            )
        case "task_state_machine_agent":
            return TaskStateMachineAgent(
                sendMessage: useCase,
                persistence: conversationPersistence,
                conversationId: id
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
        SettingsViewModel(apiKeyManager: apiKeyManager, longTermMemoryStore: longTermMemoryStore, persistence: conversationPersistence)
    }
}
