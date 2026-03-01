//
//  WeatherJSONAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class WeatherJSONAgent: BaseAgent {
    override var name: String { "Агент погоды (JSON)" }
    override var icon: String { "cloud.sun.fill" }
    override var description: String { "Возвращает информацию о погоде в виде структурированного JSON-объекта" }
    override var maxTokens: Int { 500 }
    override var availableTools: [ToolDefinition] { [.weatherTool()] }

    init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService, conversationId: UUID) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: """
                You are a weather assistant that always responds in JSON format. Use the weather tool to get weather data, then return your entire response as a valid JSON object.
                The JSON must include the following fields:
                - "location": the requested location
                - "temperature": temperature value as a number
                - "condition": weather condition as a string
                - "humidity": humidity percentage as a number
                - "summary": a brief human-readable description
                Never include any text outside of the JSON object.
                """,
            conversationId: conversationId
        )
    }
}
