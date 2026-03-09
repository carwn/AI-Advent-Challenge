//
//  MCPClient.swift
//  AI Advent Challenge
//

import Foundation

/// HTTP-клиент для Tavily MCP-сервера по протоколу JSON-RPC 2.0 over HTTP+SSE.
final class MCPClient {

    private let apiKey: String
    private var sessionId: String?
    private var requestCounter = 0
    private let session: URLSession

    /// URL с tavilyApiKey как query-параметром
    private var endpointURL: URL {
        var components = URLComponents(string: "https://mcp.tavily.com/mcp/")!
        components.queryItems = [URLQueryItem(name: "tavilyApiKey", value: apiKey)]
        return components.url!
    }

    init(apiKey: String) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public

    func fetchTools() async throws -> [MCPTool] {
        if sessionId == nil {
            // initialize может не требоваться — игнорируем ошибки
            try? await initialize()
        }
        let params = ToolsListParams()
        let req = JSONRPCRequest(id: nextId(), method: "tools/list", params: params)
        let response: MCPToolsListResponse = try await post(body: req)
        if let error = response.error {
            throw MCPClientError.serverError(code: error.code, message: error.message)
        }
        return response.result?.tools ?? []
    }

    func callTool(name: String, arguments: [String: AnyCodableValue]) async throws -> MCPToolCallResponse.ToolCallResult {
        if sessionId == nil {
            try? await initialize()
        }
        let params = ToolCallParams(name: name, arguments: JSONObject(dict: arguments))
        let req = JSONRPCRequest(id: nextId(), method: "tools/call", params: params)
        let response: MCPToolCallResponse = try await post(body: req)
        if let error = response.error {
            throw MCPClientError.serverError(code: error.code, message: error.message)
        }
        guard let result = response.result else {
            throw MCPClientError.unexpectedFormat("tools/call returned no result")
        }
        return result
    }

    // MARK: - Private

    private func initialize() async throws {
        let params = InitializeParams(
            protocolVersion: "2024-11-05",
            capabilities: InitializeParams.ClientCapabilities(),
            clientInfo: InitializeParams.ClientInfo(name: "AI-Advent-Challenge", version: "1.0")
        )
        let req = JSONRPCRequest(id: nextId(), method: "initialize", params: params)
        let response: MCPInitializeResponse = try await post(body: req)
        if let error = response.error {
            throw MCPClientError.serverError(code: error.code, message: error.message)
        }
    }

    private func nextId() -> Int {
        requestCounter += 1
        return requestCounter
    }

    private func post<T: Decodable>(body: some Encodable) async throws -> T {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sid = sessionId {
            request.setValue(sid, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        if let httpResponse = response as? HTTPURLResponse {
            if let sid = httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id") {
                sessionId = sid
            }
        }

        // Проверяем Content-Type — если SSE, парсим data: строки
        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        let jsonData: Data
        if contentType.contains("text/event-stream") {
            jsonData = try extractSSEData(from: data)
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

    /// Парсит SSE-поток и извлекает первую `data:` строку с JSON.
    private func extractSSEData(from data: Data) throws -> Data {
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
