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

        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: """
            Ты — ассистент по документации SwiftUI. \
            При каждом вопросе тебе будет передан релевантный контекст \
            из базы знаний Apple SwiftUI API. Используй его как основной источник. \
            Если контекст не содержит ответа, скажи об этом и ответь из общих знаний.
            """,
            conversationId: conversationId
        )

        let svc = ragService
        Task { @MainActor in svc.loadIndex() }
    }

    override func send(_ text: String) async throws {
        let context = await ragService.buildContext(for: text, topK: 3)
        guard !context.isEmpty else {
            try await super.send(text)
            return
        }

        let augmented = """
        [Контекст из базы знаний SwiftUI:]
        \(context)

        [Вопрос:]
        \(text)
        """

        let countBefore = conversation.messages.count
        try await super.send(augmented)

        // Заменяем augmented-текст оригинальным вопросом пользователя,
        // а контекст из БД показываем как системное summaryUsage-сообщение.
        if let idx = conversation.messages[countBefore...].firstIndex(where: { $0.role == .user }) {
            let original = conversation.messages[idx]
            conversation.messages[idx] = Message(
                id: original.id,
                role: .user,
                content: text,
                timestamp: original.timestamp
            )
            let ragNote = Message(
                role: .summaryUsage,
                content: "📚 Контекст из базы знаний SwiftUI:\n\n\(context)"
            )
            conversation.messages.insert(ragNote, at: idx + 1)
            saveConversation()
        }
    }
}

private enum RAGAgentError: Error, LocalizedError {
    case modelNotFound
    var errorDescription: String? {
        "CoreML-модель BAAI_bge-small-en-v1.5.mlmodelc не найдена в Bundle"
    }
}
