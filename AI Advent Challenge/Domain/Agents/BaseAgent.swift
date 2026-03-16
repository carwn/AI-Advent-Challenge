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
    private let conversationId: UUID

    // MARK: - Init

    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        systemPrompt: String,
        conversationId: UUID,
        compressionPolicy: (any ContextCompressionPolicy)? = nil
    ) {
        self.sendMessage = sendMessage
        self.persistence = persistence
        self.compressionPolicy = compressionPolicy
        self.systemPrompt = systemPrompt
        self.conversationId = conversationId
        self.conversation = Conversation(systemPrompt: systemPrompt)
        if let saved = persistence.load(forKey: conversationId.uuidString) {
            self.conversation = saved
        }
    }

    // MARK: - Agent

    func send(_ text: String) async throws {
        var apiConv = conversation
        var summaryUsage: UsageInfo?
        var compressionDetails: String?
        if let policy = compressionPolicy {
            (apiConv, summaryUsage, compressionDetails) = await policy.compress(conversation)
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
        if summaryUsage != nil || compressionDetails != nil {
            let compressionModelName = newMessages.last { $0.role == .assistant }?.modelName
            conversation.addMessage(Message(
                role: .summaryUsage,
                content: compressionDetails ?? "",
                modelName: compressionModelName,
                promptTokens: summaryUsage?.promptTokens,
                completionTokens: summaryUsage?.completionTokens,
                thoughtsTokens: summaryUsage?.thoughtsTokens
            ))
        }
        newMessages.forEach { conversation.addMessage($0) }
        persistence.save(conversation, forKey: conversationId.uuidString)

        let firstUser = conversation.messages.first(where: { $0.role == .user })?.content
        let lastMsg = conversation.messages.last(where: { $0.role == .user || $0.role == .assistant })
        persistence.updateRecord(
            id: conversationId,
            firstUserMessage: firstUser.map { String($0.prefix(40)) },
            lastPreview: lastMsg.map { String($0.content.prefix(80)) },
            lastDate: lastMsg?.timestamp
        )
    }

    /// Сохраняет текущее состояние conversation в persistence.
    /// Используется подклассами, которым нужно скорректировать сообщения после super.send().
    func saveConversation() {
        persistence.save(conversation, forKey: conversationId.uuidString)
    }

    func clearConversation() {
        conversation = Conversation(systemPrompt: systemPrompt)
        compressionPolicy?.reset()
        persistence.delete(forKey: conversationId.uuidString)
        persistence.updateRecord(id: conversationId, firstUserMessage: nil, lastPreview: nil, lastDate: nil)
    }
}
