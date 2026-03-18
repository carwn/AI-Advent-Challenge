//
//  RAGAgent.swift
//  AI Advent Challenge
//
//  Агент по документации SwiftUI: перед каждым LLM-вызовом ищет релевантные
//  фрагменты в базе знаний (chunks.json) через CoreML-эмбеддинги.
//  Поддерживает 4 режима RAG: basic, rerank, rewrite, full.
//

import Foundation

final class RAGAgent: BaseAgent {
    private let ragService: RAGService
    private let agentSystemPrompt: String
    private let agentConversationId: UUID
    var ragMode: RAGMode = .basic

    override var name: String        { "SwiftUI Docs" }
    override var icon: String        { "book.pages" }
    override var description: String { "Поиск по документации SwiftUI API" }
    override var maxTokens: Int      { 1500 }

    // Команды → режим
    private static let modeCommands: [String: RAGMode] = [
        "rag on": .basic,     "rag вкл": .basic,
        "/rag on": .basic,    "/rag вкл": .basic,
        "rag basic": .basic,  "rag базовый": .basic,
        "/rag basic": .basic, "/rag базовый": .basic,
        "rag off": .off,      "rag выкл": .off,
        "/rag off": .off,     "/rag выкл": .off,
        "rag rerank": .rerank,  "rag реранк": .rerank,
        "/rag rerank": .rerank, "/rag реранк": .rerank,
        "rag rewrite": .rewrite,   "rag перефраз": .rewrite,
        "/rag rewrite": .rewrite,  "/rag перефраз": .rewrite,
        "rag full": .full,    "rag полный": .full,
        "/rag full": .full,   "/rag полный": .full,
    ]

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
            Если контекст не содержит ответа, скажи об этом и ответь из общих знаний. \
            Всегда отвечай на русском языке, даже если вопрос задан на другом языке или контекст на английском.
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
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Команды переключения режима RAG
        if let newMode = Self.modeCommands[lower] {
            ragMode = newMode
            conversation.messages.append(Message(role: .user, content: text))
            let modeLabel = newMode == .off ? "⛔ RAG отключён" : "✅ RAG режим: \(newMode.displayName)"
            conversation.messages.append(Message(role: .assistant, content: modeLabel))
            saveConversation()
            return
        }

        // RAG поиск
        let ragResult: (context: String, stats: RAGSearchStats)?
        if ragMode != .off {
            let provider: ((String) async -> String?)?
            if ragMode == .rewrite || ragMode == .full {
                provider = { [weak self] q in await self?.rewriteQuery(q) }
            } else {
                provider = nil
            }
            ragResult = await ragService.buildContextWithDetails(
                for: text,
                mode: ragMode,
                rewriteQueryProvider: provider
            )
        } else {
            ragResult = nil
        }

        // userMessage = RAG context + original question
        let userMessage: String
        if let r = ragResult {
            userMessage = """
                [SwiftUI Docs Context:]
                \(r.context)

                [Question:]
                \(text)
                """
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

        // Если был RAG-контекст — добавляем stats + контент чанков как summaryUsage
        if let r = ragResult {
            let chunks = r.stats.chunkTexts
            let numberedContext = chunks.enumerated().map { i, chunk in
                "▌ Чанк \(i + 1)/\(chunks.count)\n\(chunk)"
            }.joined(separator: "\n\n")
            conversation.messages.append(Message(
                role: .summaryUsage,
                content: r.stats.summaryLine + "\n\n" + numberedContext
            ))
        }

        // Добавляем ответ ассистента
        let src = response.message
        conversation.messages.append(Message(
            role: .assistant,
            content: src.content,
            responseTime: elapsed,
            modelName: response.modelName,
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

    // MARK: — Query rewrite

    /// Переформулирует вопрос на английском для улучшения поиска по bge-small-en.
    private func rewriteQuery(_ query: String) async -> String? {
        let systemPrompt = """
            You are a search query optimizer for technical documentation search.
            Rewrite the given user question into a concise English search query
            suitable for semantic similarity search in SwiftUI API documentation.
            Output ONLY the rewritten query, nothing else. No explanations.
            """
        do {
            let response = try await sendMessage.execute(
                systemPrompt: systemPrompt,
                userMessage: query,
                tools: [],
                temperature: 0.1,
                maxTokens: 100,
                stopWords: nil
            )
            let result = response.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }
}

private enum RAGAgentError: Error, LocalizedError {
    case modelNotFound
    var errorDescription: String? {
        "CoreML-модель BAAI_bge-small-en-v1.5.mlmodelc не найдена в Bundle"
    }
}
