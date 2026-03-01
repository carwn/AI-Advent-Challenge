//
//  BaseAgent.swift
//  AI Advent Challenge
//

import Foundation

/// Базовый класс для агентов. Содержит общие зависимости и реализации `send` / `clearConversation`.
///
/// Подклассы обязаны переопределить `name`, `icon`, `description`.
/// При необходимости можно переопределить `temperature`, `maxTokens`, `stopWords`, `availableTools`.
class BaseAgent: Agent {

    // MARK: - Abstract (must override)

    var name: String { fatalError("Subclasses must override name") }
    var icon: String { fatalError("Subclasses must override icon") }
    var description: String { fatalError("Subclasses must override description") }

    // MARK: - Configurable (can override)

    var temperature: Double { 0.7 }
    var maxTokens: Int { 1000 }
    var stopWords: [String]? { nil }
    var availableTools: [ToolDefinition] { [] }

    // MARK: - Shared dependencies

    var conversation: Conversation

    let sendMessage: any SendMessageToLMMUseCase
    let persistence: ConversationPersistenceService
    let compressionPolicy: (any ContextCompressionPolicy)?
    private let systemPrompt: String
    private let persistenceKey: String

    // MARK: - Init

    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        systemPrompt: String,
        persistenceKey: String,
        compressionPolicy: (any ContextCompressionPolicy)? = nil
    ) {
        self.sendMessage = sendMessage
        self.persistence = persistence
        self.compressionPolicy = compressionPolicy
        self.systemPrompt = systemPrompt
        self.persistenceKey = persistenceKey
        self.conversation = Conversation(systemPrompt: systemPrompt)
        if let saved = persistence.load(forKey: persistenceKey) {
            self.conversation = saved
        }
    }

    // MARK: - Agent

    func send(_ text: String) async throws {
        var apiConv = conversation
        var summaryUsage: UsageInfo?
        if let policy = compressionPolicy {
            (apiConv, summaryUsage) = await policy.compress(conversation)
        }

        let countBefore = apiConv.messages.count
        let updated = try await sendMessage.execute(
            userText: text,
            conversation: apiConv,
            tools: availableTools,
            temperature: temperature,
            maxTokens: maxTokens,
            stopWords: stopWords
        )

        let newMessages = Array(updated.messages.suffix(from: countBefore))
        newMessages.forEach { conversation.addMessage($0) }
        if let usage = summaryUsage {
            conversation.addMessage(Message(
                role: .summaryUsage,
                content: "",
                promptTokens: usage.promptTokens,
                completionTokens: usage.completionTokens,
                thoughtsTokens: usage.thoughtsTokens
            ))
        }
        persistence.save(conversation, forKey: persistenceKey)
    }

    func clearConversation() {
        conversation = Conversation(systemPrompt: systemPrompt)
        compressionPolicy?.reset()
        persistence.delete(forKey: persistenceKey)
    }
}
