//
//  Conversation.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

struct Conversation: Codable {
    var messages: [Message]

    init(systemPrompt: String) {
        if systemPrompt.isEmpty {
            self.messages = []
        } else {
            self.messages = [Message(role: .system, content: systemPrompt)]
        }
    }

    mutating func addMessage(_ message: Message) {
        messages.append(message)
    }
}
