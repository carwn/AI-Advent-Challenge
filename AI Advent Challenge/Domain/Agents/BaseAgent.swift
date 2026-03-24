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

        // Используем стриминг, если провайдер поддерживает его и нет инструментов
        if sendMessage.supportsStreaming && availableTools.isEmpty {
            try await sendWithStreaming(text: text, apiConv: apiConv, summaryUsage: summaryUsage, compressionDetails: compressionDetails)
            return
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
        saveAndUpdateRecord()
    }

    // MARK: - Streaming path

    private func sendWithStreaming(
        text: String,
        apiConv: Conversation,
        summaryUsage: UsageInfo? = nil,
        compressionDetails: String? = nil
    ) async throws {
        // Добавляем сообщение пользователя
        conversation.addMessage(Message(role: .user, content: text))

        // Если была компрессия — показываем summaryUsage до стриминга
        if summaryUsage != nil || compressionDetails != nil {
            conversation.addMessage(Message(
                role: .summaryUsage,
                content: compressionDetails ?? "",
                promptTokens: summaryUsage?.promptTokens,
                completionTokens: summaryUsage?.completionTokens,
                thoughtsTokens: summaryUsage?.thoughtsTokens
            ))
        }

        let thinkingId = UUID()
        let assistantId = UUID()
        var hasThinking = false
        var hasContent = false
        var thinkingText = ""
        var contentText = ""

        for try await event in sendMessage.executeStreaming(
            userText: text,
            conversation: apiConv,
            tools: [],
            temperature: temperature,
            maxTokens: maxTokens,
            stopWords: stopWords
        ) {
            switch event {
            case .thinkingChunk(let chunk):
                thinkingText += chunk
                if !hasThinking {
                    hasThinking = true
                    conversation.addMessage(Message(
                        id: thinkingId,
                        role: .summaryUsage,
                        content: "🤔 \(thinkingText)"
                    ))
                } else {
                    conversation.updateMessageContent(id: thinkingId, content: "🤔 \(thinkingText)")
                }

            case .contentChunk(let chunk):
                contentText += chunk
                if !hasContent {
                    hasContent = true
                    conversation.addMessage(Message(
                        id: assistantId,
                        role: .assistant,
                        content: contentText
                    ))
                } else {
                    conversation.updateMessageContent(id: assistantId, content: contentText)
                }

            case .completed(let response, let elapsed):
                // Финализируем assistant message с метаданными
                if hasContent {
                    if let idx = conversation.messages.firstIndex(where: { $0.id == assistantId }) {
                        conversation.messages[idx] = Message(
                            id: assistantId,
                            role: .assistant,
                            content: contentText,
                            responseTime: elapsed,
                            modelName: response.modelName,
                            promptTokens: response.usage?.promptTokens,
                            completionTokens: response.usage?.completionTokens,
                            thoughtsTokens: response.usage?.thoughtsTokens
                        )
                    }
                } else {
                    // На случай если content не пришёл (пустой ответ)
                    conversation.addMessage(Message(
                        id: assistantId,
                        role: .assistant,
                        content: "",
                        responseTime: elapsed,
                        modelName: response.modelName,
                        promptTokens: response.usage?.promptTokens,
                        completionTokens: response.usage?.completionTokens,
                        thoughtsTokens: response.usage?.thoughtsTokens
                    ))
                }
            }
        }

        saveAndUpdateRecord()
    }

    // MARK: - Helpers

    /// Стримит thinking-блок в conversation, накапливает content и возвращает полный AgentResponse.
    /// Content-чанки НЕ добавляются в conversation — вызывающий делает это сам.
    /// Используется агентами с кастомным send() (MCPAgent, RAGAgent и т.д.)
    func streamThinkingAndGetResponse(
        systemPrompt: String,
        userMessage: String,
        temperature: Double,
        maxTokens: Int,
        stopWords: [String]? = nil
    ) async throws -> AgentResponse {
        guard sendMessage.supportsStreaming else {
            return try await sendMessage.execute(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                tools: [],
                temperature: temperature,
                maxTokens: maxTokens,
                stopWords: stopWords
            )
        }

        let thinkingId = UUID()
        var hasThinking = false
        var thinkingText = ""
        var completedResponse: AgentResponse?

        for try await event in sendMessage.executeStreaming(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            temperature: temperature,
            maxTokens: maxTokens,
            stopWords: stopWords
        ) {
            switch event {
            case .thinkingChunk(let chunk):
                thinkingText += chunk
                if !hasThinking {
                    hasThinking = true
                    conversation.addMessage(Message(
                        id: thinkingId,
                        role: .summaryUsage,
                        content: "🤔 \(thinkingText)"
                    ))
                } else {
                    conversation.updateMessageContent(id: thinkingId, content: "🤔 \(thinkingText)")
                }
            case .contentChunk:
                break  // caller handles content
            case .completed(let response, _):
                completedResponse = response
            }
        }

        guard let response = completedResponse else {
            throw NSError(domain: "BaseAgent", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Stream ended without completion event"
            ])
        }
        return response
    }

    /// Сохраняет текущее состояние conversation в persistence.
    /// Используется подклассами, которым нужно скорректировать сообщения после super.send().
    func saveConversation() {
        persistence.save(conversation, forKey: conversationId.uuidString)
    }

    private func saveAndUpdateRecord() {
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

    func clearConversation() {
        conversation = Conversation(systemPrompt: systemPrompt)
        compressionPolicy?.reset()
        persistence.delete(forKey: conversationId.uuidString)
        persistence.updateRecord(id: conversationId, firstUserMessage: nil, lastPreview: nil, lastDate: nil)
    }
}
