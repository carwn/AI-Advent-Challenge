//
//  TripleMemoryCompressionPolicy.swift
//  AI Advent Challenge
//

import Foundation

/// Политика сжатия с тремя уровнями памяти:
/// - Долговременная (LongTermMemoryStore) — свободный текст, редактируется в Settings
/// - Рабочая (KeyValueMemoryExtractor) — key-value о текущей задаче
/// - Краткосрочная — последние windowSize сообщений (скользящее окно)
final class TripleMemoryCompressionPolicy: ContextCompressionPolicy {

    static let defaultWindowSize = 5

    private static let workingMemorySystemPrompt = """
    You maintain working memory for the CURRENT TASK only. \
    Extract: goal, sub-steps done, current focus, constraints, decisions. \
    Rules: \
    (1) Return ONLY a flat JSON object — string keys and string values, no nested objects or arrays. \
    (2) Return the COMPLETE updated set. \
    (3) Remove stale entries when task changes.
    """

    private let workingMemory: KeyValueMemoryExtractor
    private let longTermMemory: LongTermMemoryStore
    private let windowSize: Int

    /// - Parameters:
    ///   - sendMessage: use case для LLM-вызовов при обновлении рабочей памяти
    ///   - windowSize: количество последних сообщений в кратковременной памяти
    ///   - persistenceKey: уникальный ключ (обычно conversationId.uuidString)
    ///   - longTermMemory: разделяемое хранилище долговременной памяти
    init(
        sendMessage: any SendMessageToLMMUseCase,
        windowSize: Int = 5,
        persistenceKey: String,
        longTermMemory: LongTermMemoryStore
    ) {
        self.windowSize = windowSize
        self.longTermMemory = longTermMemory
        self.workingMemory = KeyValueMemoryExtractor(
            sendMessage: sendMessage,
            extractionSystemPrompt: Self.workingMemorySystemPrompt,
            persistenceKey: "\(persistenceKey)_working",
            useLargerValueMerge: false
        )
    }

    // MARK: - ContextCompressionPolicy

    var description: String { "3 уровня памяти (долгосрочная + рабочая + окно \(windowSize))" }

    func compress(_ conversation: Conversation) async -> (apiConversation: Conversation, summaryUsage: UsageInfo?, details: String?) {
        let nonSystem = conversation.messages.filter { $0.role != .system && $0.role != .summaryUsage }
        var summaryUsage: UsageInfo?

        if nonSystem.count > workingMemory.processedMessageCount {
            summaryUsage = await workingMemory.update(from: conversation)
        }

        let working = workingMemory.entries
        let longTermText = longTermMemory.currentText()
        let windowCount = min(windowSize, nonSystem.count)
        let dropped = nonSystem.count - windowCount

        let details: String?
        let hasContent = !longTermText.isEmpty || !working.isEmpty || dropped > 0
        if hasContent {
            var parts: [String] = []
            var header = "история: последние \(windowCount) сообщений"
            if dropped > 0 { header += ", отброшено \(dropped)" }
            parts.append(header)
            if !longTermText.isEmpty {
                parts.append("📚 долгосрочная: \(longTermText.prefix(80))…")
            }
            parts.append(contentsOf: working.sorted { $0.key < $1.key }.map { "· \($0.key): \($0.value)" })
            details = parts.joined(separator: "\n")
        } else {
            details = nil
        }

        return (buildAPIConversation(from: conversation), summaryUsage, details)
    }

    func reset() {
        workingMemory.reset()
        // Долговременная память не сбрасывается — она управляется пользователем
    }

    // MARK: - Private

    private func buildAPIConversation(from conversation: Conversation) -> Conversation {
        var msgs: [Message] = []

        if let sys = conversation.messages.first, sys.role == .system {
            msgs.append(sys)
        }

        // Долговременная память
        let longTermText = longTermMemory.currentText()
        if !longTermText.isEmpty {
            msgs.append(Message(role: .user, content: "Долговременная память:\n\(longTermText)"))
            msgs.append(Message(role: .assistant, content: "Принял к сведению."))
        }

        // Рабочая память
        let working = workingMemory.entries
        if !working.isEmpty {
            let workingText = working
                .sorted { $0.key < $1.key }
                .map { "- \($0.key): \($0.value)" }
                .joined(separator: "\n")
            msgs.append(Message(role: .user, content: "Рабочая память:\n\(workingText)"))
            msgs.append(Message(role: .assistant, content: "Принял к сведению."))
        }

        // Краткосрочная память (скользящее окно)
        let nonSystem = conversation.messages.filter { $0.role != .system && $0.role != .summaryUsage }
        let recentMessages = Array(nonSystem.suffix(windowSize))
        msgs.append(contentsOf: recentMessages)

        var apiConv = Conversation(systemPrompt: "")
        apiConv.messages = msgs
        return apiConv
    }
}
