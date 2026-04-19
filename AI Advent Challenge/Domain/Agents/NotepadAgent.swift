//
//  NotepadAgent.swift
//  AI Advent Challenge
//

import Foundation

final class NotepadAgent: BaseAgent {
    override var name: String { "Блокнот" }
    override var icon: String { "note.text" }
    override var description: String { "Сохраняет заметки в файлы AgentState/notes/<название>.txt" }
    override var maxTokens: Int { 500 }
    override var availableTools: [ToolDefinition] { [.saveNoteTool()] }

    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        conversationId: UUID
    ) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: """
            Ты — умный блокнот-ассистент. Помогаешь пользователю сохранять заметки.
            Когда пользователь просит записать или сохранить заметку — используй инструмент save_note.
            Всегда подтверждай сохранение, указывая название файла.
            Если пользователь не указал название — придумай короткое и понятное.
            """,
            conversationId: conversationId
        )
    }
}
