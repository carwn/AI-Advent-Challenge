//
//  Conversation.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

struct Conversation: Identifiable {
    let id: UUID
    var messages: [Message]
    let agentType: AgentType
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        messages: [Message] = [],
        agentType: AgentType,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.messages = messages
        self.agentType = agentType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    mutating func addMessage(_ message: Message) {
        messages.append(message)
        updatedAt = Date()
    }
}
