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
    let createdAt: Date
    var updatedAt: Date

    init(systemPrompt: String) {
        self.id = UUID()
        self.createdAt = Date()
        self.updatedAt = Date()
        if systemPrompt.isEmpty {
            self.messages = []
        } else {
            self.messages = [Message(role: .system, content: systemPrompt)]
        }
    }

    mutating func addMessage(_ message: Message) {
        messages.append(message)
        updatedAt = Date()
    }
}
