//
//  RAGAgent.swift
//  AI Advent Challenge
//
//  Агент по документации SwiftUI: перед каждым LLM-вызовом ищет релевантные
//  фрагменты в базе знаний (chunks.json) через CoreML-эмбеддинги.
//  Поддерживает 4 режима RAG: basic, rerank, rewrite, full.
//  День 25: история диалога (последние N пар) передаётся в контекст LLM.
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

    private static let noKnowledgeThreshold: Float = 0.60
    /// Количество пар user+assistant из истории, передаваемых в контекст LLM
    private static let historyWindowSize = 3

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
            При каждом вопросе тебе передаётся пронумерованный контекст из базы знаний Apple SwiftUI API, \
            а также история предыдущих сообщений для связности диалога.

            ОБЯЗАТЕЛЬНО отвечай строго по следующему шаблону:

            ## Ответ
            <Твой ответ. Используй ссылки [1], [2], [3] в тексте для указания источников>

            ## Цитаты
            > "точная цитата из чанка" [N]
            (минимум 1 цитата из контекста)

            ## Источники
            [1] source — section
            [2] source — section

            Правила:
            — Отвечай ТОЛЬКО на основе предоставленного контекста [1], [2], [3]
            — Каждый факт должен быть подтверждён цитатой из соответствующего чанка
            — Всегда отвечай на русском языке, даже если контекст на английском
            — Если контекст недостаточно релевантен или не содержит ответа — явно скажи об этом
            — Используй историю диалога для связного продолжения разговора
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

    // MARK: - send

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
        let recentHistory = buildRecentHistory()
        let ragResult: (context: String, stats: RAGSearchStats)?
        if ragMode != .off {
            let provider: ((String) async -> String?)?
            if ragMode == .rewrite || ragMode == .full {
                provider = { [weak self] q in await self?.rewriteQuery(q, history: recentHistory) }
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

        // "Не знаю" — если RAG включён, но контекст слабый или пустой
        if ragMode != .off {
            let tooWeak = ragResult == nil || (ragResult!.stats.maxScore < Self.noKnowledgeThreshold)
            if tooWeak {
                let scoreInfo = ragResult.map { String(format: "%.0f%%", $0.stats.maxScore * 100) } ?? "0%"
                let reply = """
                    К сожалению, в базе знаний SwiftUI не найдено достаточно релевантной информации \
                    для ответа на ваш вопрос (максимальная релевантность: \(scoreInfo)).

                    Пожалуйста, уточните вопрос:
                    • Укажите конкретный SwiftUI компонент или API (например: `List`, `NavigationStack`, `@State`)
                    • Опишите, какое именно поведение вас интересует
                    • Попробуйте переключить режим RAG: `rag rewrite` или `rag full`
                    """
                conversation.messages.append(Message(role: .user, content: text))
                conversation.messages.append(Message(role: .assistant, content: reply))
                saveConversation()
                updateRecord()
                return
            }
        }

        // Строим userMessage: история + RAG контекст + вопрос
        let userMessage = buildUserMessage(text: text, ragResult: ragResult, history: recentHistory)

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
            let numberedContext = zip(r.stats.chunkTexts, r.stats.topScores).enumerated().map { i, pair in
                let (chunkText, score) = pair
                return "▌ [\(i+1)] score=\(String(format: "%.2f", score))\n\(chunkText)"
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
        updateRecord()
    }

    // MARK: - Private helpers

    /// Последние N пар user+assistant из истории в виде текста.
    private func buildRecentHistory() -> String? {
        let relevant = conversation.messages.filter {
            $0.role == .user || $0.role == .assistant
        }
        let windowCount = Self.historyWindowSize * 2
        guard relevant.count >= 2 else { return nil }
        let slice = relevant.suffix(min(windowCount, relevant.count))
        let lines = slice.map { msg -> String in
            let role = msg.role == .user ? "User" : "Assistant"
            return "\(role): \(msg.content)"
        }
        return lines.joined(separator: "\n")
    }

    /// Собирает полный userMessage: история + RAG контекст + вопрос.
    private func buildUserMessage(
        text: String,
        ragResult: (context: String, stats: RAGSearchStats)?,
        history: String?
    ) -> String {
        var parts: [String] = []

        if let history {
            parts.append("[История диалога (последние сообщения):]\n\(history)")
        }

        if let r = ragResult {
            parts.append("[SwiftUI Docs Context — \(r.stats.chunkTexts.count) источника(ов):]\n\(r.context)")
        }

        parts.append("[Текущий вопрос:]\n\(text)")

        return parts.joined(separator: "\n\n")
    }

    /// Обновляет ConversationRecord метаданные.
    private func updateRecord() {
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
    /// Если передана история — использует её для разрешения кореференций и уточнения контекста.
    private func rewriteQuery(_ query: String, history: String?) async -> String? {
        let systemPrompt = """
            You are a search query optimizer for SwiftUI API documentation semantic search.
            Rewrite the user's question into a concise English search query for the bge-small-en embedding model.
            If conversation history is provided, use it to resolve pronouns, fill in missing context, and make the query self-contained.
            Output ONLY the rewritten query, nothing else. No explanations.
            """
        let userMessage: String
        if let history {
            userMessage = """
                [Conversation history:]
                \(history)

                [Current question to rewrite:]
                \(query)
                """
        } else {
            userMessage = query
        }
        do {
            let response = try await sendMessage.execute(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
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
