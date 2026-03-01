//
//  WeatherAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class WeatherAgent: Agent {
    let name = "Агент погоды"
    let icon = "cloud.sun"
    let description = "Специализируется на предоставлении информации о погоде в любом месте"
    var conversation: Conversation

    private let sendMessage: any SendMessageToLMMUseCase
    private let persistence: ConversationPersistenceService
    private let systemPrompt = "You are a weather assistant. Use the weather tool to provide accurate weather information for any location the user asks about."
    private let availableTools: [ToolDefinition] = [.weatherTool()]
    private let maxTokens = 500
    private let stopWords: [String]? = nil
    private let temperature: Double = 0.7
    private let persistenceKey = "weather_agent"

    init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService) {
        self.sendMessage = sendMessage
        self.persistence = persistence
        self.conversation = Conversation(systemPrompt: "You are a weather assistant. Use the weather tool to provide accurate weather information for any location the user asks about.")
        if let saved = persistence.load(forKey: persistenceKey) {
            self.conversation = saved
        }
    }

    func send(_ text: String) async throws {
        conversation = try await sendMessage.execute(
            userText: text,
            conversation: conversation,
            tools: availableTools,
            temperature: temperature,
            maxTokens: maxTokens,
            stopWords: stopWords
        )
        persistence.save(conversation, forKey: persistenceKey)
    }

    func clearConversation() {
        conversation = Conversation(systemPrompt: systemPrompt)
        persistence.delete(forKey: persistenceKey)
    }
}
