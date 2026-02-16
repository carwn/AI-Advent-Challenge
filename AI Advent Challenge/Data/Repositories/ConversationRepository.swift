//
//  ConversationRepository.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

final class ConversationRepository {
    private var conversations: [UUID: Conversation] = [:]
    private let lock = NSLock()

    func getOrCreateConversation(agentType: AgentType) -> Conversation {
        lock.lock()
        defer { lock.unlock() }
        
        if let existingConversation = conversations.first(where: { $0.value.agentType == agentType })?.value {
            return existingConversation
        }

        let conversation = Conversation(
            messages: [Message(role: .system, content: agentType.systemPrompt)], agentType: agentType
        )
        conversations[conversation.id] = conversation
        return conversation
    }

    func getConversation(id: UUID) -> Conversation {
        lock.lock()
        defer { lock.unlock() }

        guard let conversation = conversations[id] else {
            fatalError("Conversation not found: \(id)")
        }
        return conversation
    }

    func updateConversation(_ conversation: Conversation) {
        lock.lock()
        defer { lock.unlock() }

        conversations[conversation.id] = conversation
    }

    func deleteConversation(id: UUID) {
        lock.lock()
        defer { lock.unlock() }

        conversations.removeValue(forKey: id)
    }

    func getAllConversations() -> [Conversation] {
        lock.lock()
        defer { lock.unlock() }

        return Array(conversations.values).sorted { $0.updatedAt > $1.updatedAt }
    }
}
