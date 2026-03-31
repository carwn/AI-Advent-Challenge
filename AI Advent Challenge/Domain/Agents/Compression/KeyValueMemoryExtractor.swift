//
//  KeyValueMemoryExtractor.swift
//  AI Advent Challenge
//

import Foundation

/// Общий алгоритм LLM-извлечения key-value памяти из диалога.
///
/// Используется `StickyFactsCompressionPolicy` и `TripleMemoryCompressionPolicy`.
final class KeyValueMemoryExtractor {
    private let sendMessage: any SendMessageToLMMUseCase
    private let extractionSystemPrompt: String
    private let stateFileURL: URL
    /// Если `true` — при обновлении существующего ключа побеждает более длинное значение
    /// (подходит для накопительных фактов StickyFacts).
    /// Если `false` — всегда используется новое значение от LLM (подходит для рабочей памяти).
    private let useLargerValueMerge: Bool

    private(set) var entries: [String: String] = [:]
    private(set) var processedMessageCount: Int = 0

    /// - Parameters:
    ///   - sendMessage: use case для LLM-вызовов при извлечении фактов
    ///   - extractionSystemPrompt: системный промпт, параметризирующий тип памяти
    ///   - persistenceKey: уникальный ключ; файл сохраняется как `AgentState/<key>.json`
    ///   - useLargerValueMerge: `true` для накопительных фактов, `false` для рабочей памяти
    init(
        sendMessage: any SendMessageToLMMUseCase,
        extractionSystemPrompt: String,
        persistenceKey: String,
        useLargerValueMerge: Bool = true
    ) {
        self.sendMessage = sendMessage
        self.extractionSystemPrompt = extractionSystemPrompt
        self.useLargerValueMerge = useLargerValueMerge
        let appSupport = FileManager.default.appSupportDirectory
        self.stateFileURL = appSupport
            .appendingPathComponent("AgentState/\(persistenceKey).json")
        loadState()
    }

    /// Извлекает новые факты из разговора. Возвращает UsageInfo если был вызов LLM.
    func update(from conversation: Conversation) async -> UsageInfo? {
        let nonSystem = conversation.messages.filter { $0.role != .system && $0.role != .summaryUsage }
        let newMessages = Array(nonSystem.dropFirst(processedMessageCount))
            .filter { $0.role == .user || $0.role == .assistant }
        guard !newMessages.isEmpty else { return nil }

        let dialogText = newMessages
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
            .joined(separator: "\n")

        let existingFactsSection: String
        if entries.isEmpty {
            existingFactsSection = "<existing_facts>none</existing_facts>"
        } else {
            let pairs = entries.sorted { $0.key < $1.key }
                .map { "  \"\($0.key)\": \"\($0.value)\"" }
                .joined(separator: ",\n")
            existingFactsSection = "<existing_facts>\n{\n\(pairs)\n}\n</existing_facts>"
        }

        let userMessage = """
        \(existingFactsSection)

        <new_messages>
        \(dialogText)
        </new_messages>

        Return the complete updated facts as a flat JSON object.
        """

        guard let response = try? await sendMessage.execute(
            systemPrompt: extractionSystemPrompt,
            userMessage: userMessage,
            tools: [],
            temperature: 0.1,
            maxTokens: 400,
            stopWords: nil
        ) else { return nil }

        let content = response.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let jsonString: String
        if let jsonStart = content.firstIndex(of: "{"), let jsonEnd = content.lastIndex(of: "}") {
            jsonString = String(content[jsonStart...jsonEnd])
        } else {
            jsonString = content
        }

        if let jsonData = jsonString.data(using: .utf8),
           let parsed = try? JSONDecoder().decode([String: String].self, from: jsonData) {
            for (key, value) in parsed where !value.isEmpty {
                if useLargerValueMerge, let existing = entries[key] {
                    entries[key] = value.count > existing.count ? value : existing
                } else {
                    entries[key] = value
                }
            }
            processedMessageCount = nonSystem.count
            saveState()
        }

        return response.usage
    }

    func reset() {
        entries = [:]
        processedMessageCount = 0
        deleteState()
    }

    // MARK: - Persistence

    private struct State: Codable {
        var facts: [String: String]
        var messageCount: Int
    }

    private func saveState() {
        let state = State(facts: entries, messageCount: processedMessageCount)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateFileURL, options: .atomic)
        }
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateFileURL),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return }
        entries = state.facts
        processedMessageCount = state.messageCount
    }

    private func deleteState() {
        try? FileManager.default.removeItem(at: stateFileURL)
    }
}
