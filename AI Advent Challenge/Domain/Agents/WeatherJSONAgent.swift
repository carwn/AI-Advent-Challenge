//
//  WeatherJSONAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class WeatherJSONAgent: Agent {
    let name = "Агент погоды (JSON)"
    let icon = "cloud.sun.fill"
    let description = "Возвращает информацию о погоде в виде структурированного JSON-объекта"
    var conversation: Conversation

    private let sendMessage: any SendMessageToLMMUseCase
    private let persistence: ConversationPersistenceService
    private let systemPrompt = """
        You are a weather assistant that always responds in JSON format. Use the weather tool to get weather data, then return your entire response as a valid JSON object.
        The JSON must include the following fields:
        - "location": the requested location
        - "temperature": temperature value as a number
        - "condition": weather condition as a string
        - "humidity": humidity percentage as a number
        - "summary": a brief human-readable description
        Never include any text outside of the JSON object.
        """
    private let availableTools: [ToolDefinition] = [.weatherTool()]
    private let maxTokens = 500
    private let stopWords: [String]? = nil
    private let temperature: Double = 0.7
    private let persistenceKey = "weather_json_agent"

    init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService) {
        self.sendMessage = sendMessage
        self.persistence = persistence
        self.conversation = Conversation(systemPrompt: systemPrompt)
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
