//
//  TripleMemoryAgent.swift
//  AI Advent Challenge
//

import Foundation

final class TripleMemoryAgent: BaseAgent {
    override var name: String { "Агент с тройной памятью" }
    override var icon: String { "brain.filled.head.profile" }
    override var description: String {
        "Три уровня памяти: долговременная (из Settings) + рабочая (текущая задача) + последние \(TripleMemoryCompressionPolicy.defaultWindowSize) сообщений."
    }

    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        conversationId: UUID,
        compressionPolicy: (any ContextCompressionPolicy)? = nil
    ) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: "You are a helpful AI assistant with a three-tier memory system. You use long-term memory (persistent facts about the user from Settings), working memory (current task context extracted automatically), and short-term memory (recent messages). Always refer to your memory layers when relevant.",
            conversationId: conversationId,
            compressionPolicy: compressionPolicy
        )
    }
}
