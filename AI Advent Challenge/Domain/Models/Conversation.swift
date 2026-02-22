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
    var totalPromptTokens: Int
    var totalCompletionTokens: Int

    init(
        id: UUID = UUID(),
        messages: [Message] = [],
        agentType: AgentType,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        totalPromptTokens: Int = 0,
        totalCompletionTokens: Int = 0
    ) {
        self.id = id
        self.messages = messages
        self.agentType = agentType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.totalPromptTokens = totalPromptTokens
        self.totalCompletionTokens = totalCompletionTokens
    }

    mutating func addMessage(_ message: Message) {
        messages.append(message)
        updatedAt = Date()
    }
}
