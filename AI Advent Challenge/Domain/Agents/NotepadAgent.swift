//
//  NotepadAgent.swift
//  AI Advent Challenge
//

import Foundation

final class NotepadAgent: BaseAgent {
    override var name: String { "Блокнот" }
    override var icon: String { "note.text" }
    override var description: String { "Ведёт заметки: сохраняет их в файлы через инструмент save_note" }
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
            You are a notepad assistant. When the user asks you to save or write a note, \
            always use the save_note tool with a concise title and the full note content. \
            After saving, confirm the title and that the note has been saved. \
            For casual conversation that doesn't require saving, reply normally without calling any tool.
            """,
            conversationId: conversationId
        )
    }
}
