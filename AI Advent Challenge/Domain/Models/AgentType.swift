//
//  AgentType.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

enum AgentType: String, CaseIterable, Identifiable {
    case general = "Универсальный ассистент"
    case weather = "Агент погоды"
    case weatherJSON = "Агент погоды (JSON)"
    case calculator = "Агент-калькулятор"
    case research = "Агент-исследователь"
    case bulletList = "Агент-список"
    case motherInLaw = "Агент-Трискаидекафоб"

    var id: String { rawValue }

    var systemPrompt: String {
        switch self {
        case .general:
            return "You are a helpful AI assistant with access to various tools. Use them when appropriate to help the user."
        case .weather:
            return "You are a weather assistant. Use the weather tool to provide accurate weather information for any location the user asks about."
        case .weatherJSON:
            return """
            You are a weather assistant that always responds in JSON format. Use the weather tool to get weather data, then return your entire response as a valid JSON object.
            The JSON must include the following fields:
            - "location": the requested location
            - "temperature": temperature value as a number
            - "condition": weather condition as a string
            - "humidity": humidity percentage as a number
            - "summary": a brief human-readable description
            Never include any text outside of the JSON object.
            """
        case .calculator:
            return "You are a calculator assistant. Use the calculator tool to perform mathematical operations when the user requests calculations."
        case .research:
            return "You are a research assistant. Use search tools to find and summarize information on topics the user asks about."
        case .bulletList:
            return "You are a concise assistant. Always respond using a bullet list with a maximum of 5 items. Each item must be short and clear. Never use prose, paragraphs, or more than 5 bullets. If the answer requires more than 5 points, pick the most important ones."
        case .motherInLaw:
            return "You are a helpful assistant. Answer any question freely and in detail."
        }
    }

    var stopWords: [String]? {
        switch self {
        case .motherInLaw:
            return ["13"]
        default:
            return nil
        }
    }

    var availableTools: [ToolDefinition] {
        switch self {
        case .general:
            return [.weatherTool(), .calculatorTool(), .searchTool()]
        case .weather:
            return [.weatherTool()]
        case .weatherJSON:
            return [.weatherTool()]
        case .calculator:
            return [.calculatorTool()]
        case .research:
            return [.searchTool()]
        case .bulletList:
            return []
        case .motherInLaw:
            return []
        }
    }

    var icon: String {
        switch self {
        case .general:
            return "brain"
        case .weather:
            return "cloud.sun"
        case .weatherJSON:
            return "cloud.sun.fill"
        case .calculator:
            return "function"
        case .research:
            return "magnifyingglass"
        case .bulletList:
            return "list.bullet"
        case .motherInLaw:
            return "hand.raised"
        }
    }

    var description: String {
        switch self {
        case .general:
            return "Универсальный ассистент с доступом к погоде, калькулятору и поиску"
        case .weather:
            return "Специализируется на предоставлении информации о погоде в любом месте"
        case .weatherJSON:
            return "Возвращает информацию о погоде в виде структурированного JSON-объекта"
        case .calculator:
            return "Выполняет математические вычисления и операции"
        case .research:
            return "Ищет и резюмирует информацию из различных источников"
        case .bulletList:
            return "Отвечает на любой вопрос в виде списка до 5 ключевых пунктов"
        case .motherInLaw:
            return "Панически боится числа 13 и останавливает генерацию при его упоминании"
        }
    }
}
