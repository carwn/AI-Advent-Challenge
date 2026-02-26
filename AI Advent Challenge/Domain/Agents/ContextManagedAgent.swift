//
//  ContextManagedAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 26.02.2026.
//

import Foundation

final class ContextManagedAgent: Agent {
    let name = "Агент с памятью"
    let icon = "memorychip"
    let description = "Полная история в UI; в API — краткое содержание вместо уже сжатых сообщений. Сжатие при >1500 токенов."
    var conversation: Conversation

    private let sendMessage: any SendingMessage
    private let persistence: ConversationPersistenceService
    private static let persistenceKey = "context_managed_agent"
    private let systemPrompt = "You are a helpful AI assistant with excellent long-term memory. You always take into account the conversation history provided."
    private let temperature: Double = 0.7
    private let maxTokens = 1000
    private let summaryTriggerTokens = 1_500

    // Сколько сообщений (из nonSystem) уже охвачены текущим summary
    private var summary: String?
    private var summaryMessageCount = 0

    init(sendMessage: any SendingMessage, persistence: ConversationPersistenceService) {
        self.sendMessage = sendMessage
        self.persistence = persistence
        self.conversation = Conversation(systemPrompt: systemPrompt)
        if let saved = persistence.load(forKey: Self.persistenceKey) {
            self.conversation = saved
        }
        loadSummaryState()
    }

    func send(_ text: String) async throws {
        let apiConv = buildAPIConversation()
        let countBefore = apiConv.messages.count
        let updated = try await sendMessage.execute(
            userText: text,
            conversation: apiConv,
            tools: [],
            temperature: temperature,
            maxTokens: maxTokens,
            stopWords: nil
        )
        let newMessages = Array(updated.messages.suffix(from: countBefore))
        newMessages.forEach { conversation.addMessage($0) }
        persistence.save(conversation, forKey: Self.persistenceKey)

        let lastResponse = newMessages.last(where: { $0.role == .assistant })
        if (lastResponse?.promptTokens ?? 0) > summaryTriggerTokens {
            await generateSummary()
        }
    }

    func clearConversation() {
        conversation = Conversation(systemPrompt: systemPrompt)
        summary = nil
        summaryMessageCount = 0
        persistence.delete(forKey: Self.persistenceKey)
        deleteSummaryState()
    }

    // MARK: - Private

    /// Строит контекст для API: system + summary pseudo-turn + несжатые сообщения
    private func buildAPIConversation() -> Conversation {
        var msgs: [Message] = []
        if let sys = conversation.messages.first, sys.role == .system {
            msgs.append(sys)
        }
        if let s = summary {
            msgs.append(Message(role: .user, content: "Краткое содержание предыдущего разговора:\n\(s)"))
            msgs.append(Message(role: .assistant, content: "Понял, учту это в ответах."))
        }
        let nonSystem = conversation.messages.filter { $0.role != .system && $0.role != .summaryUsage }
        // Отправляем только те сообщения, которые ещё не вошли в summary
        msgs.append(contentsOf: nonSystem.dropFirst(summaryMessageCount))
        var apiConv = Conversation(systemPrompt: "")
        apiConv.messages = msgs
        return apiConv
    }

    /// Суммаризирует все сообщения, не охваченные текущим summary, и обновляет summaryMessageCount
    private func generateSummary() async {
        let nonSystem = conversation.messages.filter { $0.role != .system && $0.role != .summaryUsage }
        let newMessages = Array(nonSystem.dropFirst(summaryMessageCount))
            .filter { $0.role == .user || $0.role == .assistant }
        guard !newMessages.isEmpty else { return }

        let newText = newMessages
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
            .joined(separator: "\n")

        let prompt: String
        if let existing = summary {
            prompt = """
            Current summary:
            \(existing)

            New messages to incorporate:
            \(newText)

            Update the summary to include the new messages. Return only the updated summary, in the same language as the conversation.
            """
        } else {
            prompt = "Create a concise summary of the following conversation in the same language as the conversation:\n\n\(newText)"
        }

        let summaryConv = Conversation(systemPrompt: "You are an assistant that creates concise conversation summaries. Respond only with the summary.")
        guard let result = try? await sendMessage.execute(
            userText: prompt,
            conversation: summaryConv,
            tools: [],
            temperature: 0.3,
            maxTokens: 500,
            stopWords: nil
        ), let responseMsg = result.messages.last(where: { $0.role == .assistant }) else { return }

        self.summary = responseMsg.content
        self.summaryMessageCount = nonSystem.count
        saveSummaryState()

        let accounting = Message(
            role: .summaryUsage,
            content: "",
            modelName: responseMsg.modelName,
            promptTokens: responseMsg.promptTokens,
            completionTokens: responseMsg.completionTokens,
            thoughtsTokens: responseMsg.thoughtsTokens
        )
        conversation.addMessage(accounting)
        persistence.save(conversation, forKey: Self.persistenceKey)
    }

    // MARK: - Summary persistence

    private struct SummaryState: Codable {
        var text: String
        var messageCount: Int
    }

    private func summaryFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentState/context_managed_agent_summary.json")
    }

    private func saveSummaryState() {
        guard let s = summary else { return }
        let state = SummaryState(text: s, messageCount: summaryMessageCount)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: summaryFileURL(), options: .atomic)
        }
    }

    private func loadSummaryState() {
        guard let data = try? Data(contentsOf: summaryFileURL()),
              let state = try? JSONDecoder().decode(SummaryState.self, from: data) else { return }
        summary = state.text
        summaryMessageCount = state.messageCount
    }

    private func deleteSummaryState() {
        try? FileManager.default.removeItem(at: summaryFileURL())
    }
}
