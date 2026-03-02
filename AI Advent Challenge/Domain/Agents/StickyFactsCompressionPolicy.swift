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

    static let defaultWindowSize = 5

    private static let extractionSystemPrompt = """
    You maintain a key-value memory of important facts about the USER. \
    Facts capture: goals, items already covered (letters, topics, steps), preferences, decisions. \
    Rules: \
    (1) Return ONLY a flat JSON object — string keys and string values, no nested objects or arrays. \
    (2) Return the COMPLETE updated facts — include both existing facts and any new ones from the new messages. \
    (3) For accumulative keys (e.g. covered letters/topics): include ALL previously known values PLUS the new ones. \
    (4) Do not extract facts about response format or your own instructions. \
    Example: existing {"Covered": "А Б В"}, user just covered Г Д → return {"Covered": "А Б В Г Д", ...}
    """

    private let extractor: KeyValueMemoryExtractor
    private let windowSize: Int

    /// - Parameters:
    ///   - sendMessage: use case для LLM-вызовов при извлечении фактов
    ///   - windowSize: количество последних сообщений, передаваемых в API
    ///   - persistenceKey: уникальный ключ агента; файл фактов сохраняется как `<key>_facts.json`
    init(
        sendMessage: any SendMessageToLMMUseCase,
        windowSize: Int = 5,
        persistenceKey: String
    ) {
        self.windowSize = windowSize
        self.extractor = KeyValueMemoryExtractor(
            sendMessage: sendMessage,
            extractionSystemPrompt: Self.extractionSystemPrompt,
            persistenceKey: "\(persistenceKey)_facts"
        )
    }

    // MARK: - ContextCompressionPolicy

    var description: String { "Факты + последние \(windowSize) сообщений" }

    func compress(_ conversation: Conversation) async -> (apiConversation: Conversation, summaryUsage: UsageInfo?, details: String?) {
        let nonSystem = conversation.messages.filter { $0.role != .system && $0.role != .summaryUsage }
        var summaryUsage: UsageInfo?

        if nonSystem.count > extractor.processedMessageCount {
            summaryUsage = await extractor.update(from: conversation)
        }

        let facts = extractor.entries
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
        extractor.reset()
    }

    // MARK: - Private

    private func buildAPIConversation(from conversation: Conversation) -> Conversation {
        var msgs: [Message] = []

        if let sys = conversation.messages.first, sys.role == .system {
            msgs.append(sys)
        }

        let facts = extractor.entries
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
}
