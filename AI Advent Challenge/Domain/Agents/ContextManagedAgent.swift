//
//  ContextManagedAgent.swift
//  AI Advent Challenge
//

import Foundation

final class ContextManagedAgent: Agent {
    let name = "Агент с памятью"
    let icon = "memorychip"
    let description = "Полная история в UI; в API — краткое содержание вместо уже сжатых сообщений. Сжатие при >1500 токенов."
    var conversation: Conversation

    private let sendMessage: any SendMessageToLMMUseCase
    private let persistence: ConversationPersistenceService
    private let compressionPolicy: (any ContextCompressionPolicy)?
    private static let persistenceKey = "context_managed_agent"
    private let systemPrompt = "You are a helpful AI assistant with excellent long-term memory. You always take into account the conversation history provided."
    private let temperature: Double = 0.7
    private let maxTokens = 1000

    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        compressionPolicy: (any ContextCompressionPolicy)? = nil
    ) {
        self.sendMessage = sendMessage
        self.persistence = persistence
        self.compressionPolicy = compressionPolicy
        self.conversation = Conversation(systemPrompt: systemPrompt)
        if let saved = persistence.load(forKey: Self.persistenceKey) {
            self.conversation = saved
        }
    }

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
            tools: [],
            temperature: temperature,
            maxTokens: maxTokens,
            stopWords: nil
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
        persistence.save(conversation, forKey: Self.persistenceKey)
    }

    func clearConversation() {
        conversation = Conversation(systemPrompt: systemPrompt)
        compressionPolicy?.reset()
        persistence.delete(forKey: Self.persistenceKey)
    }
}
