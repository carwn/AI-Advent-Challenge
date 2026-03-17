//
//  RAGAgent.swift
//  AI Advent Challenge
//
//  Агент по документации SwiftUI: перед каждым LLM-вызовом ищет релевантные
//  фрагменты в базе знаний (chunks.json) через CoreML-эмбеддинги.
//

import Foundation

final class RAGAgent: BaseAgent {
    private let ragService: RAGService
    private let agentSystemPrompt: String
    private let agentConversationId: UUID
    var isRAGEnabled: Bool = true

    override var name: String        { "SwiftUI Docs" }
    override var icon: String        { "book.pages" }
    override var description: String { "Поиск по документации SwiftUI API" }
    override var maxTokens: Int      { 1500 }

    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        conversationId: UUID
    ) throws {
        guard let modelURL = Bundle.main.url(
            forResource: "BAAI_bge-small-en-v1.5",
            withExtension: "mlmodelc"
        ) else {
            throw RAGAgentError.modelNotFound
        }

        self.ragService = try RAGService(coreMLModelURL: modelURL)
        self.agentConversationId = conversationId
        let prompt = """
            Ты — ассистент по документации SwiftUI. \
            При каждом вопросе тебе будет передан релевантный контекст \
            из базы знаний Apple SwiftUI API. Используй его как основной источник. \
            Если контекст не содержит ответа, скажи об этом и ответь из общих знаний.
            """
        self.agentSystemPrompt = prompt

        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: prompt,
            conversationId: conversationId
        )

        let svc = ragService
        Task { @MainActor in svc.loadIndex() }
    }

    override func send(_ text: String) async throws {
        // Команды переключения RAG
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower == "/rag on" || lower == "rag on" || lower == "/rag вкл" || lower == "rag вкл" {
            isRAGEnabled = true
            conversation.messages.append(Message(role: .user, content: text))
            conversation.messages.append(Message(role: .assistant,
                content: "✅ RAG включён. Буду использовать базу знаний SwiftUI при ответах."))
            saveConversation()
            return
        }
        if lower == "/rag off" || lower == "rag off" || lower == "/rag выкл" || lower == "rag выкл" {
            isRAGEnabled = false
            conversation.messages.append(Message(role: .user, content: text))
            conversation.messages.append(Message(role: .assistant,
                content: "⛔ RAG отключён. Буду отвечать только из общих знаний LLM."))
            saveConversation()
            return
        }

        // Формируем userMessage: только текущий запрос (без истории) + RAG-контекст если включён
        let userMessage: String
        var ragContext: String? = nil

        if isRAGEnabled {
            let context = await ragService.buildContext(for: text, topK: 3)
            if !context.isEmpty {
                ragContext = context
                userMessage = """
                    [Контекст из базы знаний SwiftUI:]
                    \(context)

                    [Вопрос:]
                    \(text)
                    """
            } else {
                userMessage = text
            }
        } else {
            userMessage = text
        }

        let startTime = Date()
        let response = try await sendMessage.execute(
            systemPrompt: agentSystemPrompt,
            userMessage: userMessage,
            tools: availableTools,
            temperature: temperature,
            maxTokens: maxTokens,
            stopWords: stopWords
        )
        let elapsed = Date().timeIntervalSince(startTime)

        // Добавляем оригинальный вопрос пользователя (без RAG-контекста)
        conversation.messages.append(Message(role: .user, content: text))

        // Если был RAG-контекст — добавляем как summaryUsage
        if let context = ragContext {
            conversation.messages.append(Message(
                role: .summaryUsage,
                content: "📚 Контекст из базы знаний SwiftUI:\n\n\(context)"
            ))
        }

        // Добавляем ответ ассистента
        let src = response.message
        conversation.messages.append(Message(
            role: .assistant,
            content: src.content,
            responseTime: elapsed,
            promptTokens: response.usage?.promptTokens,
            completionTokens: response.usage?.completionTokens,
            thoughtsTokens: response.usage?.thoughtsTokens
        ))

        saveConversation()

        let firstUser = conversation.messages.first(where: { $0.role == .user })?.content
        let lastMsg = conversation.messages.last(where: { $0.role == .user || $0.role == .assistant })
        persistence.updateRecord(
            id: agentConversationId,
            firstUserMessage: firstUser.map { String($0.prefix(40)) },
            lastPreview: lastMsg.map { String($0.content.prefix(80)) },
            lastDate: lastMsg?.timestamp
        )
    }
}

private enum RAGAgentError: Error, LocalizedError {
    case modelNotFound
    var errorDescription: String? {
        "CoreML-модель BAAI_bge-small-en-v1.5.mlmodelc не найдена в Bundle"
    }
}
