//
//  Message.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

struct Message: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    let toolCalls: [ToolCall]?
    let toolCallId: String?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
    case tool
}

struct ToolCall: Identifiable, Codable, Equatable {
    let id: String
    let type: String
    let function: FunctionCall

    struct FunctionCall: Codable, Equatable {
        let name: String
        let arguments: String // JSON string
    }
}
