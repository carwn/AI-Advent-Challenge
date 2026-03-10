//
//  MCPAgent.swift
//  AI Advent Challenge
//

import Foundation

/// Агент, подключающийся к нескольким MCP-серверам одновременно.
/// LLM используется как диспетчер: решает, какой инструмент вызвать.
final class MCPAgent: BaseAgent {

    private struct MCPServer {
        let label: String
        let client: MCPClient
        var cachedTools: [MCPTool]?
    }

    private var servers: [MCPServer] = []
    // Реестр: имя инструмента → (клиент, метка сервера)
    private var toolRegistry: [String: (client: MCPClient, label: String)] = [:]
    private let agentConversationId: UUID
    private let apiKeyManager: APIKeyManager

    override var name: String        { "MCP агент" }
    override var icon: String        { "network" }
    override var description: String { "Управляет инструментами нескольких MCP-серверов" }

    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        conversationId: UUID,
        apiKeyManager: APIKeyManager
    ) {
        self.apiKeyManager = apiKeyManager
        self.agentConversationId = conversationId
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: "Ты помощник, управляющий инструментами MCP-серверов.",
            conversationId: conversationId
        )
        buildServers()
    }

    // MARK: - send

    override func send(_ text: String) async throws {
        // 1. Добавляем сообщение пользователя
        conversation.addMessage(Message(role: .user, content: text))
        persistence.save(conversation, forKey: agentConversationId.uuidString)

        // 2. Получаем инструменты всех серверов
        let allEntries = await fetchAllTools()
        if servers.isEmpty {
            appendAssistantMessage("Нет доступных MCP-серверов. Добавьте Tavily API-ключ в Настройки → MCP серверы.")
            return
        }

        // Обновляем реестр инструментов
        toolRegistry = [:]
        for entry in allEntries {
            toolRegistry[entry.tool.name] = (client: entry.server.client, label: entry.server.label)
        }

        // 3. Вызываем LLM как диспетчера
        let systemPrompt = buildSystemPrompt(entries: allEntries)
        let dispatchResponse: AgentResponse
        do {
            dispatchResponse = try await sendMessage.execute(
                systemPrompt: systemPrompt,
                userMessage: buildDispatchMessage(currentText: text),
                tools: [],
                temperature: 0.2,
                maxTokens: 500,
                stopWords: nil
            )
        } catch {
            appendAssistantMessage("Ошибка LLM: \(error.localizedDescription)")
            return
        }

        // 4. Парсим решение LLM
        let rawResponse = dispatchResponse.message.content
        let action = parseAction(from: rawResponse)

        switch action {
        case .list:
            appendAssistantMessage(formatToolList(entries: allEntries))

        case .call(let toolName, let args):
            guard let routing = toolRegistry[toolName] else {
                appendAssistantMessage("Инструмент «\(toolName)» не найден ни на одном из MCP-серверов.")
                return
            }

            let argsPreview = args.map { key, val -> String in
                let valStr: String
                switch val {
                case .string(let s): valStr = s
                case .int(let i): valStr = "\(i)"
                case .double(let d): valStr = "\(d)"
                case .bool(let b): valStr = "\(b)"
                default: valStr = "…"
                }
                return "\(key): \(valStr)"
            }.joined(separator: ", ")
            appendInternalMessage("⚙️ MCP[\(routing.label)] → \(toolName)(\(argsPreview))")

            let mcpResult = await executeTool(client: routing.client, name: toolName, args: args)

            let resultPreview = String(mcpResult.prefix(200))
            appendInternalMessage("⚙️ MCP[\(routing.label)] ← \(resultPreview)")

            let finalReply: String
            do {
                let finalResponse = try await sendMessage.execute(
                    systemPrompt: "Ты помощник. Пользователь задал вопрос, ты вызвал инструмент \(toolName) [\(routing.label)] и получил результат. Ответь пользователю на основе этих данных на том же языке, что и вопрос.",
                    userMessage: "Вопрос: \(text)\n\nРезультат инструмента \(toolName):\n\(mcpResult)",
                    tools: [],
                    temperature: 0.7,
                    maxTokens: 1000,
                    stopWords: nil
                )
                finalReply = finalResponse.message.content
            } catch {
                finalReply = mcpResult
            }
            appendAssistantMessage(finalReply)

        case .chat(let reply):
            appendAssistantMessage(reply)

        case .unknown:
            appendAssistantMessage(rawResponse)
        }
    }

    // MARK: - Servers setup

    private func buildServers() {
        servers = []
        // Carwn — всегда доступен, использует Streamable HTTP transport (POST /mcp)
        servers.append(MCPServer(
            label: "Carwn",
            client: MCPClient(url: URL(string: "https://carwn-carwnmcp-39c3.twc1.net/mcp")!)
        ))
        // Tavily — только если есть API-ключ, использует Streamable HTTP transport
        if let key = try? apiKeyManager.getAPIKey(for: .tavily), !key.isEmpty {
            servers.insert(MCPServer(
                label: "Tavily",
                client: MCPClient(apiKey: key)
            ), at: 0)
        }
    }

    // MARK: - Tool fetching

    private func fetchAllTools() async -> [(tool: MCPTool, server: MCPServer)] {
        // Пересоздаём серверы, чтобы подхватить актуальный Tavily-ключ
        buildServers()

        var results: [(tool: MCPTool, server: MCPServer)] = []
        await withTaskGroup(of: [(tool: MCPTool, server: MCPServer)].self) { group in
            for server in servers {
                group.addTask {
                    let tools = (try? await server.client.fetchTools()) ?? []
                    return tools.map { (tool: $0, server: server) }
                }
            }
            for await batch in group {
                results.append(contentsOf: batch)
            }
        }
        return results
    }

    // MARK: - Private helpers

    private func appendInternalMessage(_ content: String) {
        conversation.addMessage(Message(role: .summaryUsage, content: content))
        persistence.save(conversation, forKey: agentConversationId.uuidString)
    }

    private func appendAssistantMessage(_ content: String) {
        conversation.addMessage(Message(role: .assistant, content: content))
        persistence.save(conversation, forKey: agentConversationId.uuidString)

        let firstUser = conversation.messages.first(where: { $0.role == .user })?.content
        let lastMsg = conversation.messages.last(where: { $0.role == .user || $0.role == .assistant })
        persistence.updateRecord(
            id: agentConversationId,
            firstUserMessage: firstUser.map { String($0.prefix(40)) },
            lastPreview: lastMsg.map { String($0.content.prefix(80)) },
            lastDate: lastMsg?.timestamp
        )
    }

    private func executeTool(client: MCPClient, name: String, args: [String: AnyCodableValue]) async -> String {
        do {
            let result = try await client.callTool(name: name, arguments: args)
            return formatResult(result, toolName: name)
        } catch {
            return "Ошибка при вызове «\(name)»: \(error.localizedDescription)"
        }
    }

    private func buildDispatchMessage(currentText: String) -> String {
        let history = conversation.messages
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(5)
        guard !history.isEmpty else { return currentText }
        let historyLines = history.map { msg in
            let role = msg.role == .user ? "Пользователь" : "Ассистент"
            return "\(role): \(msg.content)"
        }.joined(separator: "\n")
        return "Контекст предыдущих сообщений:\n\(historyLines)\n\nТекущий запрос: \(currentText)"
    }

    private func buildSystemPrompt(entries: [(tool: MCPTool, server: MCPServer)]) -> String {
        let toolsText: String
        if entries.isEmpty {
            toolsText = "(нет инструментов)"
        } else {
            toolsText = entries.enumerated().map { (i, entry) -> String in
                var lines = ["\(i + 1). \(entry.tool.name) [\(entry.server.label)]"]
                if let desc = entry.tool.description { lines.append("   \(desc)") }
                let params = entry.tool.parameters()
                if !params.isEmpty {
                    let paramList = params.map { p in
                        let req = p.required ? "*" : ""
                        let t = p.type.map { "(\($0))" } ?? ""
                        return "\(p.name)\(req) \(t)".trimmingCharacters(in: .whitespaces)
                    }.joined(separator: ", ")
                    lines.append("   Params: \(paramList)")
                }
                return lines.joined(separator: "\n")
            }.joined(separator: "\n\n")
        }

        return """
        Ты диспетчер инструментов MCP-серверов.

        Доступные инструменты (* — обязательный параметр):
        \(toolsText)

        Проанализируй запрос пользователя и верни СТРОГО один из трёх JSON-форматов (без комментариев, без markdown):

        1. Показать список инструментов:
           {"action":"list"}

        2. Вызвать инструмент:
           {"action":"call","tool":"имя_инструмента","args":{"параметр":"значение"}}

        3. Ответить текстом (если запрос не связан с инструментами):
           {"action":"chat","reply":"твой ответ"}

        Возвращай ТОЛЬКО JSON, без пояснений.
        """
    }

    private func formatToolList(entries: [(tool: MCPTool, server: MCPServer)]) -> String {
        guard !entries.isEmpty else { return "Список инструментов MCP пуст." }

        // Группируем по метке сервера
        var grouped: [(label: String, tools: [MCPTool])] = []
        for entry in entries {
            if let idx = grouped.firstIndex(where: { $0.label == entry.server.label }) {
                grouped[idx].tools.append(entry.tool)
            } else {
                grouped.append((label: entry.server.label, tools: [entry.tool]))
            }
        }

        var lines: [String] = []
        for group in grouped {
            lines.append("**\(group.label)** (\(group.tools.count) инструментов):\n")
            for (i, tool) in group.tools.enumerated() {
                lines.append("\(i + 1). **\(tool.name)**")
                if let desc = tool.description {
                    lines.append("   \(desc)")
                }
                let params = tool.parameters()
                if !params.isEmpty {
                    lines.append("   Параметры:")
                    for p in params {
                        let req = p.required ? " *" : ""
                        let typeStr = p.type.map { " (\($0))" } ?? ""
                        let descStr = p.description.map { ": \($0)" } ?? ""
                        lines.append("   • \(p.name)\(req)\(typeStr)\(descStr)")
                    }
                }
                lines.append("")
            }
        }
        lines.append("(* — обязательный параметр)")
        return lines.joined(separator: "\n")
    }

    private func formatResult(_ result: MCPToolCallResponse.ToolCallResult, toolName: String) -> String {
        let texts = result.content.compactMap { $0.text }.joined(separator: "\n\n")
        let prefix = result.isError == true ? "⚠️ Ошибка «\(toolName)»" : "Результат «\(toolName)»"
        if texts.isEmpty { return "\(prefix): (пустой ответ)" }
        return "\(prefix):\n\n\(texts)"
    }

    // MARK: - Action parsing

    private enum LLMAction {
        case list
        case call(tool: String, args: [String: AnyCodableValue])
        case chat(reply: String)
        case unknown
    }

    private func parseAction(from text: String) -> LLMAction {
        var searchFrom = text.startIndex
        while searchFrom < text.endIndex {
            guard let jsonStr = extractFirstJSON(from: String(text[searchFrom...])),
                  let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONDecoder().decode([String: AnyCodableValue].self, from: data)
            else { break }

            if let action = resolveAction(from: obj) {
                return action
            }

            if let range = text.range(of: jsonStr, range: searchFrom..<text.endIndex) {
                searchFrom = range.upperBound
            } else {
                break
            }
        }
        return .unknown
    }

    private func resolveAction(from obj: [String: AnyCodableValue]) -> LLMAction? {
        guard case .string(let action) = obj["action"] else { return nil }

        switch action {
        case "list":
            return .list

        case "call":
            guard case .string(let toolName) = obj["tool"] else { return nil }
            var args: [String: AnyCodableValue] = [:]
            if case .object(let argsObj) = obj["args"] { args = argsObj }
            return .call(tool: toolName, args: args)

        case "chat":
            if case .string(let reply) = obj["reply"] { return .chat(reply: reply) }
            return nil

        default:
            let toolName: String
            if case .string(let t) = obj["tool"] {
                toolName = t
            } else {
                toolName = action
            }
            var args: [String: AnyCodableValue] = [:]
            if case .object(let argsObj) = obj["args"] { args = argsObj }
            return .call(tool: toolName, args: args)
        }
    }

    private func extractFirstJSON(from text: String) -> String? {
        guard let startIdx = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escape = false
        var idx = startIdx
        while idx < text.endIndex {
            let ch = text[idx]
            if escape {
                escape = false
            } else if ch == "\\" && inString {
                escape = true
            } else if ch == "\"" {
                inString.toggle()
            } else if !inString {
                if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[startIdx...idx])
                    }
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }
}
