//
//  SummaryContextCompressionPolicy.swift
//  AI Advent Challenge
//

import Foundation

/// Реализация ContextCompressionPolicy на основе summary.
/// При превышении порога токенов генерирует (или обновляет) краткое содержание
/// предыдущей части разговора и подставляет его вместо уже сжатых сообщений.
final class SummaryContextCompressionPolicy: ContextCompressionPolicy {

    private let sendMessage: any SendMessageToLMMUseCase
    private let summaryTriggerTokens: Int
    private let stateFileURL: URL

    private var summary: String?
    private var summaryMessageCount = 0

    /// - Parameters:
    ///   - sendMessage: use case для генерации summary
    ///   - summaryTriggerTokens: порог promptTokens последнего ответа, при котором запускается сжатие
    ///   - persistenceKey: уникальный ключ агента; файл summary сохраняется как `<key>_summary.json`
    init(
        sendMessage: any SendMessageToLMMUseCase,
        summaryTriggerTokens: Int = 500,
        persistenceKey: String
    ) {
        self.sendMessage = sendMessage
        self.summaryTriggerTokens = summaryTriggerTokens
        self.stateFileURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentState/\(persistenceKey)_summary.json")
        loadState()
    }

    // MARK: - ContextCompressionPolicy

    var description: String { "Summary при >\(summaryTriggerTokens) токенов" }

    func compress(_ conversation: Conversation) async -> (apiConversation: Conversation, summaryUsage: UsageInfo?, details: String?) {
        var summaryUsage: UsageInfo?

        let lastResponse = conversation.messages.last { $0.role == .assistant }
        if (lastResponse?.promptTokens ?? 0) > summaryTriggerTokens {
            summaryUsage = await generateSummary(from: conversation)
        }

        let nonSystem = conversation.messages.filter { $0.role != .system && $0.role != .summaryUsage }
        let windowCount = nonSystem.count - summaryMessageCount
        let compressed = summary != nil || summaryMessageCount > 0

        let details: String?
        if compressed {
            var parts = ["история: последние \(windowCount) сообщений"]
            if let s = summary { parts.append(s) }
            details = parts.joined(separator: "\n")
        } else {
            details = nil
        }
        return (buildAPIConversation(from: conversation), summaryUsage, details)
    }

    func reset() {
        summary = nil
        summaryMessageCount = 0
        deleteState()
    }

    // MARK: - Private: построение сжатого контекста

    private func buildAPIConversation(from conversation: Conversation) -> Conversation {
        var msgs: [Message] = []

        if let sys = conversation.messages.first, sys.role == .system {
            msgs.append(sys)
        }

        if let s = summary {
            msgs.append(Message(role: .user, content: "Краткое содержание предыдущего разговора:\n\(s)"))
            msgs.append(Message(role: .assistant, content: "Понял, учту это в ответах."))
        }

        let nonSystem = conversation.messages.filter { $0.role != .system && $0.role != .summaryUsage }
        msgs.append(contentsOf: nonSystem.dropFirst(summaryMessageCount))

        var apiConv = Conversation(systemPrompt: "")
        apiConv.messages = msgs
        return apiConv
    }

    // MARK: - Private: генерация / обновление summary

    /// Суммаризирует несжатые сообщения. Возвращает UsageInfo потраченных токенов.
    private func generateSummary(from conversation: Conversation) async -> UsageInfo? {
        let nonSystem = conversation.messages.filter { $0.role != .system && $0.role != .summaryUsage }
        let newMessages = Array(nonSystem.dropFirst(summaryMessageCount))
            .filter { $0.role == .user || $0.role == .assistant }
        guard !newMessages.isEmpty else { return nil }

        let newText = newMessages
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
            .joined(separator: "\n")

        let userMessage: String
        if let existing = summary {
            userMessage = """
            Current summary:
            \(existing)

            New messages to incorporate:
            \(newText)

            Update the summary to include the new messages. Return only the updated summary, in the same language as the conversation.
            """
        } else {
            userMessage = "Create a concise summary of the following conversation in the same language as the conversation:\n\n\(newText)"
        }

        guard let response = try? await sendMessage.execute(
            systemPrompt: "You are an assistant that creates concise conversation summaries. Respond only with the summary.",
            userMessage: userMessage,
            tools: [],
            temperature: 0.3,
            maxTokens: 500,
            stopWords: nil
        ) else { return nil }

        summary = response.message.content
        summaryMessageCount = nonSystem.count
        saveState()

        return response.usage
    }

    // MARK: - Persistence

    private struct State: Codable {
        var text: String
        var messageCount: Int
    }

    private func saveState() {
        guard let s = summary else { return }
        let state = State(text: s, messageCount: summaryMessageCount)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateFileURL, options: .atomic)
        }
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateFileURL),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return }
        summary = state.text
        summaryMessageCount = state.messageCount
    }

    private func deleteState() {
        try? FileManager.default.removeItem(at: stateFileURL)
    }
}
