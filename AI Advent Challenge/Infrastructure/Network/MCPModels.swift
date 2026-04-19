//
//  MCPModels.swift
//  AI Advent Challenge
//

import Foundation

// MARK: - JSON-RPC Request

struct JSONRPCRequest<P: Encodable>: Encodable {
    let jsonrpc: String = "2.0"
    let id: Int
    let method: String
    let params: P?
}

// MARK: - Initialize

struct InitializeParams: Encodable {
    let protocolVersion: String
    let capabilities: ClientCapabilities
    let clientInfo: ClientInfo

    struct ClientCapabilities: Encodable {}
    struct ClientInfo: Encodable {
        let name: String
        let version: String
    }
}

// MARK: - Tools List

struct ToolsListParams: Encodable {}

// MARK: - Tool Call

struct ToolCallParams: Encodable {
    let name: String
    let arguments: JSONObject
}

// MARK: - JSONObject

typealias JSONObject = [String: AnyCodableValue]

indirect enum AnyCodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let v = try? container.decode(Bool.self) { self = .bool(v); return }
        if let v = try? container.decode(Int.self) { self = .int(v); return }
        if let v = try? container.decode(Double.self) { self = .double(v); return }
        if let v = try? container.decode(String.self) { self = .string(v); return }
        if let v = try? container.decode([AnyCodableValue].self) { self = .array(v); return }
        if let v = try? container.decode([String: AnyCodableValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown value type")
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v):  try container.encode(v)
        case .int(let v):     try container.encode(v)
        case .double(let v):  try container.encode(v)
        case .bool(let v):    try container.encode(v)
        case .array(let v):   try container.encode(v)
        case .object(let v):  try container.encode(v)
        case .null:           try container.encodeNil()
        }
    }
}

// MARK: - MCP Tool

struct MCPTool: Decodable {
    let name: String
    let description: String?
    /// Сырая JSON Schema — хранится как JSONObject для гибкости
    let inputSchema: JSONObject?

    /// Извлекает список параметров из inputSchema
    func parameters() -> [(name: String, type: String?, description: String?, required: Bool)] {
        guard let schema = inputSchema else { return [] }

        guard case .object(let props) = schema["properties"] else { return [] }

        var requiredSet: Set<String> = []
        if case .array(let req) = schema["required"] {
            for item in req {
                if case .string(let s) = item { requiredSet.insert(s) }
            }
        }

        return props.sorted(by: { $0.key < $1.key }).map { (paramName, propVal) in
            var typeStr: String? = nil
            var descStr: String? = nil
            if case .object(let prop) = propVal {
                if case .string(let t) = prop["type"] { typeStr = t }
                if case .string(let d) = prop["description"] { descStr = d }
            }
            return (name: paramName, type: typeStr, description: descStr, required: requiredSet.contains(paramName))
        }
    }
}

// MARK: - Responses

struct MCPInitializeResponse: Decodable {
    let result: InitializeResult?
    let error: JSONRPCError?

    struct InitializeResult: Decodable {
        let protocolVersion: String?
    }
}

struct MCPToolsListResponse: Decodable {
    let result: ToolsResult?
    let error: JSONRPCError?

    struct ToolsResult: Decodable {
        let tools: [MCPTool]
    }
}

struct MCPToolCallResponse: Decodable {
    let result: ToolCallResult?
    let error: JSONRPCError?

    struct ToolCallResult: Decodable {
        let content: [MCPContent]
        let isError: Bool?
    }
}

struct MCPContent: Decodable {
    let type: String
    let text: String?
}

struct JSONRPCError: Decodable {
    let code: Int
    let message: String
}

// MARK: - Errors

enum MCPClientError: LocalizedError {
    case serverError(code: Int, message: String)
    case unexpectedFormat(String)
    case initializationFailed

    var errorDescription: String? {
        switch self {
        case .serverError(let code, let message):
            return "MCP server error \(code): \(message)"
        case .unexpectedFormat(let detail):
            return "MCP format error: \(detail)"
        case .initializationFailed:
            return "MCP initialization failed"
        }
    }
}
