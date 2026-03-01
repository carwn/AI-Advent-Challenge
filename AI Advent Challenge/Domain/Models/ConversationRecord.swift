//
//  ConversationRecord.swift
//  AI Advent Challenge
//

import Foundation

struct ConversationRecord: Identifiable, Codable {
    let id: UUID
    let agentKey: String      // "general_agent", "weather_agent" и т.д.
    let agentName: String
    let agentIcon: String
    var title: String         // дата создания; обновляется из первого user-сообщения
    var lastMessagePreview: String?
    var lastMessageDate: Date?
    let createdAt: Date
    var parentId: UUID? = nil // nil = корневой диалог
}
