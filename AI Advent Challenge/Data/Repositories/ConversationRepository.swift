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

    func setSystemPromptForAgent(_ agentType: AgentType, prompt: String) {
        lock.lock()
        defer { lock.unlock() }

        if let id = conversations.first(where: { $0.value.agentType == agentType })?.key {
            var conversation = conversations[id]!
            if let idx = conversation.messages.firstIndex(where: { $0.role == .system }) {
                let old = conversation.messages[idx]
                conversation.messages[idx] = Message(
                    id: old.id, role: .system, content: prompt, timestamp: old.timestamp
                )
            } else {
                conversation.messages.insert(Message(role: .system, content: prompt), at: 0)
            }
            conversations[id] = conversation
        } else {
            let conversation = Conversation(
                messages: [Message(role: .system, content: prompt)],
                agentType: agentType
            )
            conversations[conversation.id] = conversation
        }
    }

    func clearConversation(id: UUID) {
        lock.lock()
        defer { lock.unlock() }

        guard var conversation = conversations[id] else { return }
        conversation.messages = conversation.messages.filter { $0.role == .system }
        conversation.updatedAt = Date()
        conversations[id] = conversation
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
