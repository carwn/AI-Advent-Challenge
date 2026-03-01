//
//  LLMMessage.swift
//  AI Advent Challenge
//
//  Created by Claude on 01.03.2026.
//

import Foundation

/// Исходящее сообщение для API-запроса к LLM-провайдеру.
/// Может иметь любую роль (system, user, assistant, tool).
struct LLMMessage {
    let role: MessageRole
    let content: String
    let toolCalls: [ToolCall]?
    let toolCallId: String?

    init(role: MessageRole, content: String, toolCalls: [ToolCall]? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}

/// Входящий ответ от LLM-провайдера.
/// Всегда имеет роль assistant — поле role отсутствует.
struct LLMResponse {
    let content: String
    let toolCalls: [ToolCall]?

    init(content: String, toolCalls: [ToolCall]? = nil) {
        self.content = content
        self.toolCalls = toolCalls
    }
}

extension Message {
    func toLLMMessage() -> LLMMessage {
        LLMMessage(role: role, content: content, toolCalls: toolCalls, toolCallId: toolCallId)
    }
}
