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
        let items: ItemsSchema?

        struct ItemsSchema: Codable {
            let type: String
        }

        enum CodingKeys: String, CodingKey {
            case type
            case description
            case enumValues = "enum"
            case items
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
                            enumValues: nil,
                            items: nil
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
                            enumValues: ["add", "subtract", "multiply", "divide"],
                            items: nil
                        ),
                        "operands": PropertySchema(
                            type: "array",
                            description: "The numbers to operate on",
                            enumValues: nil,
                            items: PropertySchema.ItemsSchema(type: "number")
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
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: ["query"]
                )
            )
        )
    }

    static func saveNote() -> ToolDefinition {
        ToolDefinition(
            type: "function",
            function: FunctionDefinition(
                name: "save_note",
                description: "Сохраняет текстовую заметку с заданным заголовком и содержимым",
                parameters: ParametersSchema(
                    type: "object",
                    properties: [
                        "title": PropertySchema(
                            type: "string",
                            description: "Заголовок заметки (используется как имя файла)",
                            enumValues: nil,
                            items: nil
                        ),
                        "content": PropertySchema(
                            type: "string",
                            description: "Содержимое заметки",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: ["title", "content"]
                )
            )
        )
    }

    static func listNotes() -> ToolDefinition {
        ToolDefinition(
            type: "function",
            function: FunctionDefinition(
                name: "list_notes",
                description: "Возвращает список сохранённых заметок",
                parameters: ParametersSchema(
                    type: "object",
                    properties: [:],
                    required: nil
                )
            )
        )
    }
}
