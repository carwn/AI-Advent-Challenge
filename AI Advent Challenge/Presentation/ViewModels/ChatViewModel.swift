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
    @Published var ragMode: RAGMode = .off
    var ragEnabled: Bool { ragMode != .off }   // backward compat

    var totalPromptTokens: Int { messages.reduce(0) { $0 + ($1.promptTokens ?? 0) } }
    var totalCompletionTokens: Int { messages.reduce(0) { $0 + ($1.completionTokens ?? 0) } }
    var totalThoughtsTokens: Int { messages.reduce(0) { $0 + ($1.thoughtsTokens ?? 0) } }

    var agentName: String { agent.name }
    var agentIcon: String { agent.icon }
    var agentCompressionPolicy: (any ContextCompressionPolicy)? { agent.compressionPolicy }
    var isRAGAgent: Bool { agent is RAGAgent }

    private let agent: any Agent
    let historyStore: MessageHistoryStore
    private var cancellables = Set<AnyCancellable>()

    func setRAGMode(_ mode: RAGMode) {
        let command = "rag \(mode.rawValue)"
        isLoading = true
        Task {
            try? await agent.send(command)
            messages = agent.conversation.messages.filter { $0.role != .system }
            if let ra = agent as? RAGAgent { ragMode = ra.ragMode }
            isLoading = false
        }
    }

    init(agent: any Agent, historyStore: MessageHistoryStore) {
        self.agent = agent
        self.historyStore = historyStore
        self.messages = agent.conversation.messages.filter { $0.role != .system }
        self.ragMode = (agent as? RAGAgent)?.ragMode ?? .off

        historyStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        if let mcpAgent = agent as? MCPAgent {
            mcpAgent.backgroundMessagePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in
                    guard let self else { return }
                    self.messages = self.agent.conversation.messages.filter { $0.role != .system }
                }
                .store(in: &cancellables)
        }
    }

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        historyStore.add(text)
        inputText = ""
        messages.append(Message(role: .user, content: text))
        isLoading = true
        error = nil

        Task {
            // Polling task: updates UI every 150ms while send() is running.
            // Runs on MainActor and gets control during await suspensions (LLM calls).
            let pollTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard !Task.isCancelled, let self else { break }
                    let agentMessages = self.agent.conversation.messages.filter { $0.role != .system }
                    // Не перезаписываем messages, пока агент ещё не добавил новые данные
                    // (иначе оптимистично добавленное сообщение пользователя исчезнет)
                    if agentMessages.count >= self.messages.count {
                        self.messages = agentMessages
                    }
                }
            }

            do {
                try await agent.send(text)
            } catch {
                self.error = error.localizedDescription
                messages.removeLast()
            }

            pollTask.cancel()
            messages = agent.conversation.messages.filter { $0.role != .system }
            if let ra = agent as? RAGAgent { ragMode = ra.ragMode }
            isLoading = false
        }
    }

    func clearConversation() {
        agent.clearConversation()
        messages = []
        error = nil
    }
}
