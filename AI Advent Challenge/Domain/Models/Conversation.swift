//
//  Conversation.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

struct Conversation: Codable, Sendable {
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

    mutating func updateMessageContent(id: UUID, content: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        let old = messages[idx]
        messages[idx] = Message(
            id: old.id, role: old.role, content: content,
            timestamp: old.timestamp, toolCalls: old.toolCalls,
            toolCallId: old.toolCallId, responseTime: old.responseTime,
            modelName: old.modelName, promptTokens: old.promptTokens,
            completionTokens: old.completionTokens, thoughtsTokens: old.thoughtsTokens
        )
    }
}
