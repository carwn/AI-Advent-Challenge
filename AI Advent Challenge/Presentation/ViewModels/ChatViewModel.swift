//
//  ChatViewModel.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published private(set) var systemPrompt: String = ""
    @Published private(set) var totalPromptTokens: Int = 0
    @Published private(set) var totalCompletionTokens: Int = 0
    private(set) var agentType: AgentType = .general

    private let sendMessageUseCase: SendMessageUseCase
    private let setCustomPromptAction: ((String) -> Void)?
    private let onTokensUpdated: ((Int, Int) -> Void)?
    private var conversationId: UUID!
    private var cancellables = Set<AnyCancellable>()

    let historyStore: MessageHistoryStore
    let temperatureStore: TemperatureStore

    init(
        sendMessageUseCase: SendMessageUseCase,
        conversation: Conversation,
        historyStore: MessageHistoryStore,
        temperatureStore: TemperatureStore,
        setCustomPromptAction: ((String) -> Void)? = nil,
        onTokensUpdated: ((Int, Int) -> Void)? = nil
    ) {
        self.sendMessageUseCase = sendMessageUseCase
        self.historyStore = historyStore
        self.temperatureStore = temperatureStore
        self.setCustomPromptAction = setCustomPromptAction
        self.onTokensUpdated = onTokensUpdated
        setup(conversation)

        historyStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        temperatureStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func setup(_ conversation: Conversation) {
        self.conversationId = conversation.id
        self.agentType = conversation.agentType
        self.messages = conversation.messages.filter { $0.role != .system }
        self.systemPrompt = conversation.messages.first(where: { $0.role == .system })?.content
            ?? conversation.agentType.systemPrompt
        self.totalPromptTokens = conversation.totalPromptTokens
        self.totalCompletionTokens = conversation.totalCompletionTokens
    }

    func useAsCustomAgentPrompt(_ text: String) {
        setCustomPromptAction?(text)
    }

    func clearConversation() {
        sendMessageUseCase.clearConversation(conversationId: conversationId)
        messages = []
        totalPromptTokens = 0
        totalCompletionTokens = 0
        onTokensUpdated?(0, 0)
        error = nil
    }

    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let messageText = inputText
        historyStore.add(messageText)
        inputText = ""
        isLoading = true
        error = nil

        // Add user message immediately
        let userMessage = Message(role: .user, content: messageText)
        messages.append(userMessage)

        Task {
            do {
                let startTime = Date()
                let response = try await sendMessageUseCase.execute(
                    message: messageText,
                    conversationId: conversationId
                )
                let elapsed = Date().timeIntervalSince(startTime)

                let msg = response.message
                let timedMessage = Message(
                    id: msg.id,
                    role: msg.role,
                    content: msg.content,
                    timestamp: msg.timestamp,
                    toolCalls: msg.toolCalls,
                    toolCallId: msg.toolCallId,
                    responseTime: elapsed
                )
                messages.append(timedMessage)
                if let usage = response.usage {
                    totalPromptTokens += usage.promptTokens
                    totalCompletionTokens += usage.completionTokens
                    onTokensUpdated?(totalPromptTokens, totalCompletionTokens)
                }
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }
}
