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

    var totalPromptTokens: Int { messages.reduce(0) { $0 + ($1.promptTokens ?? 0) } }
    var totalCompletionTokens: Int { messages.reduce(0) { $0 + ($1.completionTokens ?? 0) } }
    var totalThoughtsTokens: Int { messages.reduce(0) { $0 + ($1.thoughtsTokens ?? 0) } }

    private let agent: any Agent
    let historyStore: MessageHistoryStore
    private var cancellables = Set<AnyCancellable>()

    init(agent: any Agent, historyStore: MessageHistoryStore) {
        self.agent = agent
        self.historyStore = historyStore
        self.messages = agent.conversation.messages.filter { $0.role != .system }

        historyStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
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
            do {
                _ = try await agent.send(text)
                messages = agent.conversation.messages.filter { $0.role != .system }
            } catch {
                messages.removeLast()
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    func clearConversation() {
        agent.clearConversation()
        messages = []
        error = nil
    }
}
