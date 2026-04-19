//
//  NotepadAgent.swift
//  AI Advent Challenge
//

import Foundation

final class NotepadAgent: BaseAgent {
    override var name: String { "Блокнот" }
    override var icon: String { "note.text" }
    override var description: String { "Сохраняет и отображает текстовые заметки" }
    override var availableTools: [ToolDefinition] { [.saveNote(), .listNotes()] }

    init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService, conversationId: UUID) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: """
            Ты — умный блокнот. Ты умеешь сохранять заметки с помощью инструмента save_note(title, content) и показывать список заметок с помощью list_notes().
            Когда пользователь просит сохранить заметку — используй save_note.
            Когда пользователь просит показать заметки — используй list_notes.
            """,
            conversationId: conversationId
        )
    }
}
