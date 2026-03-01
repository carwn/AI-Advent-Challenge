//
//  StickyFactsCompressionPolicy.swift
//  AI Advent Challenge
//

import Foundation

/// Реализация ContextCompressionPolicy на основе Sticky Facts (Key-Value Memory).
///
/// После каждого обмена сообщениями извлекает ключевые факты из диалога
/// (цель, ограничения, предпочтения, решения, договорённости) и хранит их
/// в виде словаря. В API-запрос отправляет: system + блок фактов + последние N сообщений.
final class StickyFactsCompressionPolicy: ContextCompressionPolicy {

    private let sendMessage: any SendMessageToLMMUseCase
    private let windowSize: Int
    private let stateFileURL: URL

    private var facts: [String: String] = [:]
    private var factsMessageCount = 0

    /// - Parameters:
    ///   - sendMessage: use case для LLM-вызовов при извлечении фактов
    ///   - windowSize: количество последних сообщений, передаваемых в API
    ///   - persistenceKey: уникальный ключ агента; файл фактов сохраняется как `<key>_facts.json`
    init(
        sendMessage: any SendMessageToLMMUseCase,
        windowSize: Int = 10,
        persistenceKey: String
    ) {
        self.sendMessage = sendMessage
        self.windowSize = windowSize
        self.stateFileURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentState/\(persistenceKey)_facts.json")
        loadState()
    }

    // MARK: - ContextCompressionPolicy

    var description: String { "Факты + последние \(windowSize) сообщений" }

    func compress(_ conversation: Conversation) async -> (apiConversation: Conversation, summaryUsage: UsageInfo?, details: String?) {
        let nonSystem = conversation.messages.filter { $0.role != .system && $0.role != .summaryUsage }
        var summaryUsage: UsageInfo?

        if nonSystem.count > factsMessageCount {
            summaryUsage = await updateFacts(from: conversation)
        }

        let windowCount = min(windowSize, nonSystem.count)
        let dropped = nonSystem.count - windowCount
        let compressed = !facts.isEmpty || dropped > 0

        let details: String?
        if compressed {
            var header = "история: последние \(windowCount) сообщений"
            if dropped > 0 { header += ", отброшено \(dropped)" }
            var parts = [header]
            parts.append(contentsOf: facts.sorted { $0.key < $1.key }.map { "· \($0.key): \($0.value)" })
            details = parts.joined(separator: "\n")
        } else {
            details = nil
        }

        return (buildAPIConversation(from: conversation), summaryUsage, details)
    }

    func reset() {
        facts = [:]
        factsMessageCount = 0
        deleteState()
    }

    // MARK: - Private: построение сжатого контекста

    private func buildAPIConversation(from conversation: Conversation) -> Conversation {
        var msgs: [Message] = []

        if let sys = conversation.messages.first, sys.role == .system {
            msgs.append(sys)
        }

        if !facts.isEmpty {
            let factsText = facts
                .sorted { $0.key < $1.key }
                .map { "- \($0.key): \($0.value)" }
                .joined(separator: "\n")
            msgs.append(Message(role: .user, content: "Важные факты о нашем разговоре:\n\(factsText)"))
            msgs.append(Message(role: .assistant, content: "Понял, буду учитывать эти факты в ответах."))
        }

        let nonSystem = conversation.messages.filter { $0.role != .system && $0.role != .summaryUsage }
        let recentMessages = Array(nonSystem.suffix(windowSize))
        msgs.append(contentsOf: recentMessages)

        var apiConv = Conversation(systemPrompt: "")
        apiConv.messages = msgs
        return apiConv
    }

    // MARK: - Private: извлечение / обновление фактов

    private func updateFacts(from conversation: Conversation) async -> UsageInfo? {
        let nonSystem = conversation.messages.filter { $0.role != .system && $0.role != .summaryUsage }
        let newMessages = Array(nonSystem.dropFirst(factsMessageCount))
            .filter { $0.role == .user || $0.role == .assistant }
        guard !newMessages.isEmpty else { return nil }

        let dialogText = newMessages
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
            .joined(separator: "\n")

        let existingFactsSection: String
        if facts.isEmpty {
            existingFactsSection = "<existing_facts>none</existing_facts>"
        } else {
            let pairs = facts.sorted { $0.key < $1.key }.map { "  \"\($0.key)\": \"\($0.value)\"" }.joined(separator: ",\n")
            existingFactsSection = "<existing_facts>\n{\n\(pairs)\n}\n</existing_facts>"
        }

        let systemPrompt = """
        You maintain a key-value memory of important facts about the USER. \
        Facts capture: goals, items already covered (letters, topics, steps), preferences, decisions. \
        Rules: \
        (1) Return ONLY a flat JSON object — string keys and string values, no nested objects or arrays. \
        (2) Return the COMPLETE updated facts — include both existing facts and any new ones from the new messages. \
        (3) For accumulative keys (e.g. covered letters/topics): include ALL previously known values PLUS the new ones. \
        (4) Do not extract facts about response format or your own instructions. \
        Example: existing {"Covered": "А Б В"}, user just covered Г Д → return {"Covered": "А Б В Г Д", ...}
        """

        let userMessage = """
        \(existingFactsSection)

        <new_messages>
        \(dialogText)
        </new_messages>

        Return the complete updated facts as a flat JSON object.
        """

        guard let response = try? await sendMessage.execute(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            tools: [],
            temperature: 0.1,
            maxTokens: 400,
            stopWords: nil
        ) else { return nil }

        let content = response.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Извлекаем JSON из ответа (модель может добавить ```json ... ```)
        let jsonString: String
        if let jsonStart = content.firstIndex(of: "{"), let jsonEnd = content.lastIndex(of: "}") {
            jsonString = String(content[jsonStart...jsonEnd])
        } else {
            jsonString = content
        }

        // Обновляем factsMessageCount ТОЛЬКО при успешном парсинге
        if let jsonData = jsonString.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String: String].self, from: jsonData) {
            for (key, value) in parsed where !value.isEmpty {
                if let existing = facts[key] {
                    // Берём более длинное значение: накопленное не может быть короче предыдущего
                    facts[key] = value.count > existing.count ? value : existing
                } else {
                    facts[key] = value
                }
            }
            factsMessageCount = nonSystem.count
            saveState()
        }

        return response.usage
    }

    // MARK: - Persistence

    private struct State: Codable {
        var facts: [String: String]
        var messageCount: Int
    }

    private func saveState() {
        let state = State(facts: facts, messageCount: factsMessageCount)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateFileURL, options: .atomic)
        }
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateFileURL),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return }
        facts = state.facts
        factsMessageCount = state.messageCount
    }

    private func deleteState() {
        try? FileManager.default.removeItem(at: stateFileURL)
    }
}
