//
//  TavilyMCPAgent.swift
//  AI Advent Challenge
//

import Foundation

/// Агент, подключающийся к Tavily MCP-серверу.
/// LLM используется как диспетчер: решает, какой инструмент вызвать.
final class TavilyMCPAgent: BaseAgent {

    private var mcpClient: MCPClient?
    private var cachedTools: [MCPTool]?
    private let agentConversationId: UUID
    private let apiKeyManager: APIKeyManager

    override var name: String        { "Tavily MCP" }
    override var icon: String        { "network" }
    override var description: String { "Использует инструменты Tavily MCP-сервера" }

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
            systemPrompt: "Ты помощник, управляющий инструментами Tavily MCP-сервера.",
            conversationId: conversationId
        )
    }

    // MARK: - send

    override func send(_ text: String) async throws {
        // 1. Добавляем сообщение пользователя
        conversation.addMessage(Message(role: .user, content: text))
        persistence.save(conversation, forKey: agentConversationId.uuidString)

        // 2. Получаем или создаём MCPClient с актуальным ключом
        let client: MCPClient
        do {
            client = try resolvedMCPClient()
        } catch {
            appendAssistantMessage(error.localizedDescription)
            return
        }

        // 3. Получаем список инструментов (с кэшем)
        let tools: [MCPTool]
        do {
            if let cached = cachedTools {
                tools = cached
            } else {
                tools = try await client.fetchTools()
                cachedTools = tools
            }
        } catch {
            appendAssistantMessage("Не удалось получить список инструментов MCP: \(error.localizedDescription)")
            return
        }

        // 3. Вызываем LLM как диспетчера
        let systemPrompt = buildSystemPrompt(tools: tools)
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
            appendAssistantMessage(formatToolList(tools))

        case .call(let toolName, let args):
            // Показываем запрос к MCP
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
            appendInternalMessage("⚙️ MCP → \(toolName)(\(argsPreview))")

            let mcpResult = await executeTool(client: client, name: toolName, args: args)

            // Показываем краткий ответ от MCP
            let resultPreview = String(mcpResult.prefix(200))
            appendInternalMessage("⚙️ MCP ← \(resultPreview)")
            // Передаём вопрос пользователя и результат MCP обратно в LLM для итогового ответа
            let finalReply: String
            do {
                let finalResponse = try await sendMessage.execute(
                    systemPrompt: "Ты помощник. Пользователь задал вопрос, ты вызвал инструмент \(toolName) и получил результат. Ответь пользователю на основе этих данных на том же языке, что и вопрос.",
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

    private func resolvedMCPClient() throws -> MCPClient {
        if let existing = mcpClient { return existing }
        guard let key = try? apiKeyManager.getAPIKey(for: .tavily), !key.isEmpty else {
            throw MCPClientError.unexpectedFormat(
                "Tavily API ключ не задан. Добавьте его в Настройки → Tavily MCP."
            )
        }
        let client = MCPClient(apiKey: key)
        mcpClient = client
        return client
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
            .suffix(5)  // последние 5 сообщений включая текущее
        guard !history.isEmpty else { return currentText }
        let historyLines = history.map { msg in
            let role = msg.role == .user ? "Пользователь" : "Ассистент"
            return "\(role): \(msg.content)"
        }.joined(separator: "\n")
        return "Контекст предыдущих сообщений:\n\(historyLines)\n\nТекущий запрос: \(currentText)"
    }

    private func buildSystemPrompt(tools: [MCPTool]) -> String {
        // Строим компактный текстовый список инструментов для системного промпта
        let toolsText = tools.enumerated().map { (i, tool) -> String in
            var lines = ["\(i + 1). \(tool.name)"]
            if let desc = tool.description { lines.append("   \(desc)") }
            let params = tool.parameters()
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

        return """
        Ты диспетчер инструментов Tavily MCP-сервера.

        Доступные инструменты (* — обязательный параметр):
        \(toolsText.isEmpty ? "(нет инструментов)" : toolsText)

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

    private func formatToolList(_ tools: [MCPTool]) -> String {
        guard !tools.isEmpty else { return "Список инструментов Tavily MCP пуст." }

        var lines = ["Доступные инструменты Tavily MCP (\(tools.count)):\n"]
        for (i, tool) in tools.enumerated() {
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
        // Перебираем все JSON-объекты в тексте, пока не найдём валидный action
        var searchFrom = text.startIndex
        while searchFrom < text.endIndex {
            guard let jsonStr = extractFirstJSON(from: String(text[searchFrom...])),
                  let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONDecoder().decode([String: AnyCodableValue].self, from: data)
            else { break }

            if let action = resolveAction(from: obj) {
                return action
            }

            // Сдвигаемся за найденный JSON и ищем следующий
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
            // Fallback: LLM использовала имя инструмента как action (напр. "tavily_search")
            // Если есть поле "tool" или само action похоже на имя инструмента — трактуем как call
            let toolName: String
            if case .string(let t) = obj["tool"] {
                toolName = t
            } else {
                toolName = action  // само action и есть имя инструмента
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
