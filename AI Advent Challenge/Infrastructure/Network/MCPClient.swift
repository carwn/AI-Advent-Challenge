//
//  MCPClient.swift
//  AI Advent Challenge
//

import Foundation

/// HTTP-клиент для MCP-сервера по протоколу JSON-RPC 2.0.
/// Использует Streamable HTTP транспорт: POST → ответ напрямую в теле или SSE.
final class MCPClient {

    private let baseURL: URL
    private var streamableSessionId: String?
    private var requestCounter = 0
    private let session: URLSession

    // MARK: - Init

    /// Инициализатор для Tavily: строит URL с ?tavilyApiKey=.
    init(apiKey: String) {
        var components = URLComponents(string: "https://mcp.tavily.com/mcp/")!
        components.queryItems = [URLQueryItem(name: "tavilyApiKey", value: apiKey)]
        self.baseURL = components.url!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    /// Инициализатор для произвольного MCP-сервера.
    init(url: URL) {
        self.baseURL = url
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public

    func fetchTools() async throws -> [MCPTool] {
        if streamableSessionId == nil { try? await initStreamable() }
        let params = ToolsListParams()
        let req = JSONRPCRequest(id: nextId(), method: "tools/list", params: params)
        let response: MCPToolsListResponse = try await postStreamable(body: req)
        if let error = response.error {
            throw MCPClientError.serverError(code: error.code, message: error.message)
        }
        return response.result?.tools ?? []
    }

    func callTool(name: String, arguments: [String: AnyCodableValue]) async throws -> MCPToolCallResponse.ToolCallResult {
        if streamableSessionId == nil { try? await initStreamable() }
        let params = ToolCallParams(name: name, arguments: JSONObject(dict: arguments))
        let req = JSONRPCRequest(id: nextId(), method: "tools/call", params: params)
        let response: MCPToolCallResponse = try await postStreamable(body: req)
        if let error = response.error {
            throw MCPClientError.serverError(code: error.code, message: error.message)
        }
        guard let result = response.result else {
            throw MCPClientError.unexpectedFormat("tools/call returned no result")
        }
        return result
    }

    // MARK: - Streamable HTTP

    private func initStreamable() async throws {
        let params = InitializeParams(
            protocolVersion: "2024-11-05",
            capabilities: InitializeParams.ClientCapabilities(),
            clientInfo: InitializeParams.ClientInfo(name: "AI-Advent-Challenge", version: "1.0")
        )
        let req = JSONRPCRequest(id: nextId(), method: "initialize", params: params)
        let response: MCPInitializeResponse = try await postStreamable(body: req)
        if let error = response.error {
            throw MCPClientError.serverError(code: error.code, message: error.message)
        }
    }

    private func postStreamable<T: Decodable>(body: some Encodable) async throws -> T {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sid = streamableSessionId {
            request.setValue(sid, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse,
           let sid = http.value(forHTTPHeaderField: "Mcp-Session-Id") {
            streamableSessionId = sid
        }

        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        let jsonData: Data
        if contentType.contains("text/event-stream") {
            jsonData = try extractSSEPayload(from: data)
        } else {
            jsonData = data
        }

        do {
            return try JSONDecoder().decode(T.self, from: jsonData)
        } catch {
            let raw = String(data: jsonData, encoding: .utf8) ?? "<binary>"
            throw MCPClientError.unexpectedFormat("Decode failed: \(error). Raw: \(raw.prefix(500))")
        }
    }

    // MARK: - Helpers

    private func nextId() -> Int {
        requestCounter += 1
        return requestCounter
    }

    /// Извлекает первую `data:` строку из SSE-ответа.
    private func extractSSEPayload(from data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MCPClientError.unexpectedFormat("SSE: cannot decode as UTF-8")
        }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("data:") {
                let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if !payload.isEmpty, let d = payload.data(using: .utf8) {
                    return d
                }
            }
        }
        throw MCPClientError.unexpectedFormat("SSE: no data: line found")
    }
}
