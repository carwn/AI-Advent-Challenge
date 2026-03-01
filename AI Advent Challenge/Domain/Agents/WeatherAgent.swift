//
//  WeatherAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class WeatherAgent: BaseAgent {
    override var name: String { "Агент погоды" }
    override var icon: String { "cloud.sun" }
    override var description: String { "Специализируется на предоставлении информации о погоде в любом месте" }
    override var maxTokens: Int { 500 }
    override var availableTools: [ToolDefinition] { [.weatherTool()] }

    init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: "You are a weather assistant. Use the weather tool to provide accurate weather information for any location the user asks about.",
            persistenceKey: "weather_agent"
        )
    }
}
