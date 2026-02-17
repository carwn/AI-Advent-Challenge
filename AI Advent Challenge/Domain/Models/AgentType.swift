//
//  AgentType.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

enum AgentType: String, CaseIterable, Identifiable {
    case general = "General Assistant"
    case weather = "Weather Agent"
    case calculator = "Calculator Agent"
    case research = "Research Agent"

    var id: String { rawValue }

    var systemPrompt: String {
        switch self {
        case .general:
            return "You are a helpful AI assistant with access to various tools. Use them when appropriate to help the user."
        case .weather:
            return "You are a weather assistant. Use the weather tool to provide accurate weather information for any location the user asks about."
        case .calculator:
            return "You are a calculator assistant. Use the calculator tool to perform mathematical operations when the user requests calculations."
        case .research:
            return "You are a research assistant. Use search tools to find and summarize information on topics the user asks about."
        }
    }

    var availableTools: [ToolDefinition] {
        switch self {
        case .general:
            return [.weatherTool(), .calculatorTool(), .searchTool()]
        case .weather:
            return [.weatherTool()]
        case .calculator:
            return [.calculatorTool()]
        case .research:
            return [.searchTool()]
        }
    }

    var icon: String {
        switch self {
        case .general:
            return "brain"
        case .weather:
            return "cloud.sun"
        case .calculator:
            return "function"
        case .research:
            return "magnifyingglass"
        }
    }

    var description: String {
        switch self {
        case .general:
            return "Multi-purpose assistant with access to weather, calculator, and search tools"
        case .weather:
            return "Specialized in providing weather information for any location"
        case .calculator:
            return "Performs mathematical calculations and operations"
        case .research:
            return "Searches and summarizes information from various sources"
        }
    }
}
