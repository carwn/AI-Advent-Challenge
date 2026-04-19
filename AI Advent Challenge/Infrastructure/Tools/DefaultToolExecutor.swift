//
//  DefaultToolExecutor.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

final class DefaultToolExecutor: ToolExecutor {
    private let weatherService: WeatherService?
    private let calculatorService: CalculatorService?
    private let searchService: SearchService?
    private let notesPersistenceService: NotesPersistenceService?

    init(
        weatherService: WeatherService? = nil,
        calculatorService: CalculatorService? = nil,
        searchService: SearchService? = nil,
        notesPersistenceService: NotesPersistenceService? = nil
    ) {
        self.weatherService = weatherService ?? DefaultWeatherService()
        self.calculatorService = calculatorService ?? DefaultCalculatorService()
        self.searchService = searchService ?? DefaultSearchService()
        self.notesPersistenceService = notesPersistenceService
    }

    func canExecute(toolName: String) -> Bool {
        switch toolName {
        case "get_weather":
            return weatherService != nil
        case "calculate":
            return calculatorService != nil
        case "search":
            return searchService != nil
        case "save_note":
            return notesPersistenceService != nil
        default:
            return false
        }
    }

    func execute(_ toolCall: ToolCall) async throws -> String {
        let functionName = toolCall.function.name
        let arguments = toolCall.function.arguments

        switch functionName {
        case "get_weather":
            return try await executeWeather(arguments: arguments)
        case "calculate":
            return try executeCalculate(arguments: arguments)
        case "search":
            return try await executeSearch(arguments: arguments)
        case "save_note":
            return try executeSaveNote(arguments: arguments)
        default:
            throw ToolExecutionError.unsupportedTool(functionName)
        }
    }

    private func executeWeather(arguments: String) async throws -> String {
        guard let service = weatherService else {
            throw ToolExecutionError.unsupportedTool("get_weather")
        }

        guard let data = arguments.data(using: .utf8),
              let params = try? JSONDecoder().decode(WeatherParams.self, from: data) else {
            throw ToolExecutionError.invalidArguments(arguments)
        }

        let result = try await service.getWeather(location: params.location)
        return result.toJSON()
    }

    private func executeCalculate(arguments: String) throws -> String {
        guard let service = calculatorService else {
            throw ToolExecutionError.unsupportedTool("calculate")
        }

        guard let data = arguments.data(using: .utf8),
              let params = try? JSONDecoder().decode(CalculatorParams.self, from: data) else {
            throw ToolExecutionError.invalidArguments(arguments)
        }

        let result = try service.calculate(
            operation: params.operation,
            operands: params.operands
        )
        return "{\"result\": \(result)}"
    }

    private func executeSaveNote(arguments: String) throws -> String {
        guard let service = notesPersistenceService else {
            throw ToolExecutionError.unsupportedTool("save_note")
        }

        guard let data = arguments.data(using: .utf8),
              let params = try? JSONDecoder().decode(SaveNoteParams.self, from: data) else {
            throw ToolExecutionError.invalidArguments(arguments)
        }

        try service.saveNote(title: params.title, content: params.content)
        return "{\"status\": \"saved\", \"file\": \"AgentState/notes/\(params.title).txt\"}"
    }

    private func executeSearch(arguments: String) async throws -> String {
        guard let service = searchService else {
            throw ToolExecutionError.unsupportedTool("search")
        }

        guard let data = arguments.data(using: .utf8),
              let params = try? JSONDecoder().decode(SearchParams.self, from: data) else {
            throw ToolExecutionError.invalidArguments(arguments)
        }

        let results = try await service.search(query: params.query)
        return results.toJSON()
    }
}

// MARK: - Errors

enum ToolExecutionError: LocalizedError {
    case unsupportedTool(String)
    case invalidArguments(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedTool(let name):
            return "Tool '\(name)' is not supported"
        case .invalidArguments(let details):
            return "Invalid tool arguments: \(details)"
        case .executionFailed(let reason):
            return "Tool execution failed: \(reason)"
        }
    }
}

// MARK: - Tool Parameters

struct WeatherParams: Codable {
    let location: String
}

struct CalculatorParams: Codable {
    let operation: String
    let operands: [Double]
}

struct SearchParams: Codable {
    let query: String
}

struct SaveNoteParams: Codable {
    let title: String
    let content: String
}

// MARK: - Tool Service Protocols

protocol WeatherService {
    func getWeather(location: String) async throws -> WeatherResult
}

protocol CalculatorService {
    func calculate(operation: String, operands: [Double]) throws -> Double
}

protocol SearchService {
    func search(query: String) async throws -> SearchResults
}

// MARK: - Result Models

struct WeatherResult: Codable {
    let location: String
    let temperature: Double
    let condition: String
    let humidity: Int

    func toJSON() -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

struct SearchResults: Codable {
    let results: [SearchResult]

    struct SearchResult: Codable {
        let title: String
        let snippet: String
        let url: String
    }

    func toJSON() -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}

// MARK: - Default Implementations (Mock Services)

final class DefaultWeatherService: WeatherService {
    func getWeather(location: String) async throws -> WeatherResult {
        // Mock implementation with realistic delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Return mock weather data
        return WeatherResult(
            location: location,
            temperature: Double.random(in: 15...30),
            condition: ["Sunny", "Cloudy", "Rainy", "Partly Cloudy"].randomElement() ?? "Sunny",
            humidity: Int.random(in: 40...80)
        )
    }
}

final class DefaultCalculatorService: CalculatorService {
    func calculate(operation: String, operands: [Double]) throws -> Double {
        guard !operands.isEmpty else {
            throw ToolExecutionError.invalidArguments("No operands provided")
        }

        switch operation {
        case "add":
            return operands.reduce(0, +)
        case "subtract":
            guard operands.count >= 2 else {
                throw ToolExecutionError.invalidArguments("Subtraction requires at least 2 operands")
            }
            return operands.dropFirst().reduce(operands[0], -)
        case "multiply":
            return operands.reduce(1, *)
        case "divide":
            guard operands.count >= 2 else {
                throw ToolExecutionError.invalidArguments("Division requires at least 2 operands")
            }
            guard !operands.dropFirst().contains(0) else {
                throw ToolExecutionError.executionFailed("Division by zero")
            }
            return operands.dropFirst().reduce(operands[0], /)
        default:
            throw ToolExecutionError.unsupportedTool(operation)
        }
    }
}

final class DefaultSearchService: SearchService {
    func search(query: String) async throws -> SearchResults {
        // Mock implementation with realistic delay
        try await Task.sleep(nanoseconds: 700_000_000) // 0.7 seconds

        // Return mock search results
        return SearchResults(results: [
            .init(
                title: "Result 1 for: \(query)",
                snippet: "This is a mock search result. In a real implementation, this would search the internet for: \(query)",
                url: "https://example.com/result1"
            ),
            .init(
                title: "Result 2 for: \(query)",
                snippet: "Another mock result providing relevant information about your query.",
                url: "https://example.com/result2"
            ),
            .init(
                title: "Result 3 for: \(query)",
                snippet: "Third result with more details about: \(query)",
                url: "https://example.com/result3"
            )
        ])
    }
}
