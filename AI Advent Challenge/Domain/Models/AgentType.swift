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
    case bulletList = "Агент-список"
    case stop13 = "Агент-Трискаидекафоб"
    case stepByStep = "Пошаговый решатель"
    case promptCrafter = "Промпт-инженер"
    case multiExpert = "Совет экспертов"

    var id: String { rawValue }

    var systemPrompt: String {
        switch self {
        case .general:
            return "You are a helpful AI assistant."
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
        case .bulletList:
            return "You are a concise assistant. Always respond using a bullet list with a maximum of 5 items. Each item must be short and clear. Never use prose, paragraphs, or more than 5 bullets. If the answer requires more than 5 points, pick the most important ones."
        case .stop13:
            return "You are a helpful assistant. Answer any question freely and in detail."
        case .stepByStep:
            return """
            You are a methodical problem-solving assistant. For every user request:
            1. Restate the problem briefly.
            2. Break it down into clear, numbered steps.
            3. Execute each step explicitly, showing your reasoning.
            4. Provide a final summary with the answer.
            Never skip steps. Never jump to conclusions without showing your work.
            Keep each step concise — one or two sentences per step is enough.
            """
        case .promptCrafter:
            return """
            You are an expert prompt engineer. When the user describes a task or goal,
            your job is NOT to solve it — instead, craft a precise, effective prompt
            that another AI agent could use to solve it optimally.

            Structure your output as:
            - **Роль агента**: who the agent should be
            - **Задача**: clear description of what to do
            - **Формат ответа**: expected output format
            - **Ограничения**: any constraints or rules

            Output only the crafted prompt, no commentary.
            Be concise — each section should be 1–3 sentences at most.
            """
        case .multiExpert:
            return """
            You are a multi-expert reasoning system. For every user request:

            1. **Identify Experts**: Determine 3 distinct expert roles most relevant to the task. Name each role clearly.

            2. **Expert Opinions**: For each expert, present their analysis in this format:
               ### [Expert Role]
               [Their perspective, reasoning, and recommendation]

            3. **Synthesis**: After all three opinions, add a section:
               ### Итоговый вывод
               Synthesize the key insights from all three experts into a final, balanced conclusion.

            Always complete all three expert opinions before synthesizing.
            Keep each expert's opinion concise — 3–5 sentences maximum per expert.
            """
        }
    }

    var stopWords: [String]? {
        switch self {
        case .stop13:
            return ["13"]
        case .general, .weather, .weatherJSON, .bulletList,
             .stepByStep, .promptCrafter, .multiExpert:
            return nil
        }
    }

    var availableTools: [ToolDefinition] {
        switch self {
        case .general:
            return []
        case .weather:
            return [.weatherTool()]
        case .weatherJSON:
            return [.weatherTool()]
        case .bulletList:
            return []
        case .stop13:
            return []
        case .stepByStep, .promptCrafter, .multiExpert:
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
        case .bulletList:
            return "list.bullet"
        case .stop13:
            return "hand.raised"
        case .stepByStep:
            return "list.number"
        case .promptCrafter:
            return "text.cursor"
        case .multiExpert:
            return "person.3"
        }
    }

    var description: String {
        switch self {
        case .general:
            return "Универсальный ассистент"
        case .weather:
            return "Специализируется на предоставлении информации о погоде в любом месте"
        case .weatherJSON:
            return "Возвращает информацию о погоде в виде структурированного JSON-объекта"
        case .bulletList:
            return "Отвечает на любой вопрос в виде списка до 5 ключевых пунктов"
        case .stop13:
            return "Панически боится числа 13 и останавливает генерацию при его упоминании"
        case .stepByStep:
            return "Разбивает любую задачу на последовательные шаги и решает методично"
        case .promptCrafter:
            return "Составляет оптимальный промпт для другого AI-агента"
        case .multiExpert:
            return "Привлекает трёх экспертов, получает их мнения и синтезирует вывод"
        }
    }

    var maxTokens: Int {
        switch self {
        case .general:      return 1000
        case .weather:      return 500
        case .weatherJSON:  return 500
        case .bulletList:   return 300
        case .stop13:       return 1000
        case .stepByStep:   return 1000
        case .promptCrafter: return 800
        case .multiExpert:  return 2000
        }
    }
}
