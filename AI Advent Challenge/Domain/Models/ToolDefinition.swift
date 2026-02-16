//
//  ToolDefinition.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

struct ToolDefinition: Codable {
    let type: String
    let function: FunctionDefinition

    struct FunctionDefinition: Codable {
        let name: String
        let description: String
        let parameters: ParametersSchema
    }

    struct ParametersSchema: Codable {
        let type: String
        let properties: [String: PropertySchema]
        let required: [String]?
    }

    struct PropertySchema: Codable {
        let type: String
        let description: String
        let enumValues: [String]?

        enum CodingKeys: String, CodingKey {
            case type
            case description
            case enumValues = "enum"
        }
    }

    // Фабричные методы для создания стандартных tools
    static func weatherTool() -> ToolDefinition {
        ToolDefinition(
            type: "function",
            function: FunctionDefinition(
                name: "get_weather",
                description: "Get the current weather in a given location",
                parameters: ParametersSchema(
                    type: "object",
                    properties: [
                        "location": PropertySchema(
                            type: "string",
                            description: "The city and state, e.g. San Francisco, CA",
                            enumValues: nil
                        )
                    ],
                    required: ["location"]
                )
            )
        )
    }

    static func calculatorTool() -> ToolDefinition {
        ToolDefinition(
            type: "function",
            function: FunctionDefinition(
                name: "calculate",
                description: "Perform a mathematical calculation",
                parameters: ParametersSchema(
                    type: "object",
                    properties: [
                        "operation": PropertySchema(
                            type: "string",
                            description: "The operation to perform",
                            enumValues: ["add", "subtract", "multiply", "divide"]
                        ),
                        "operands": PropertySchema(
                            type: "array",
                            description: "The numbers to operate on",
                            enumValues: nil
                        )
                    ],
                    required: ["operation", "operands"]
                )
            )
        )
    }

    static func searchTool() -> ToolDefinition {
        ToolDefinition(
            type: "function",
            function: FunctionDefinition(
                name: "search",
                description: "Search for information on the internet",
                parameters: ParametersSchema(
                    type: "object",
                    properties: [
                        "query": PropertySchema(
                            type: "string",
                            description: "The search query",
                            enumValues: nil
                        )
                    ],
                    required: ["query"]
                )
            )
        )
    }
}
