//
//  MCPAgent.swift
//  AI Advent Challenge
//

import Foundation
import Combine

/// Агент, подключающийся к нескольким MCP-серверам одновременно.
/// LLM используется как диспетчер: решает, какой инструмент вызвать.
final class MCPAgent: BaseAgent {

    private struct MCPServer {
        let label: String
        let client: MCPClient
        var cachedTools: [MCPTool]?
    }

    // MARK: - Scheduled tasks model

    private struct ScheduledTask: Codable, Identifiable {
        let id: UUID
        let description: String   // краткое описание задачи
        let intervalSeconds: Int  // >= 10
        let createdAt: Date
    }

    // MARK: - State

    private var servers: [MCPServer] = []
    // Реестр: имя инструмента → (клиент, метка сервера)
    private var toolRegistry: [String: (client: MCPClient, label: String)] = [:]
    private let agentConversationId: UUID
    private let apiKeyManager: APIKeyManager
    private let currentModelName: String?

    private var scheduledTasks: [ScheduledTask] = []
    private var timerTasks: [UUID: Task<Void, Never>] = [:]
    private let tasksFileURL: URL

    private let backgroundMessageSubject = PassthroughSubject<Void, Never>()
    var backgroundMessagePublisher: AnyPublisher<Void, Never> {
        backgroundMessageSubject.eraseToAnyPublisher()
    }

    override var name: String        { "MCP агент" }
    override var icon: String        { "network" }
    override var description: String { "Управляет инструментами нескольких MCP-серверов" }

    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        conversationId: UUID,
        apiKeyManager: APIKeyManager,
        modelName: String? = nil
    ) {
        self.apiKeyManager = apiKeyManager
        self.agentConversationId = conversationId
        self.currentModelName = modelName

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.tasksFileURL = appSupport.appendingPathComponent("AgentState/\(conversationId.uuidString)_mcp_tasks.json")

        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: "Ты помощник, управляющий инструментами MCP-серверов.",
            conversationId: conversationId
        )
        buildServers()
        loadScheduledTasks()
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

        // 3. Агентный цикл: LLM-диспетчер → MCP-вызов → накопление результатов → повтор
        let systemPrompt = buildSystemPrompt(entries: allEntries)
        let maxIterations = 10
        var iterationContext = ""
        var iteration = 0

        while iteration < maxIterations {
            let dispatchResponse: AgentResponse
            do {
                dispatchResponse = try await sendMessage.execute(
                    systemPrompt: systemPrompt,
                    userMessage: buildDispatchMessage(currentText: text, mcpContext: iterationContext),
                    tools: [],
                    temperature: 0.2,
                    maxTokens: 500,
                    stopWords: nil
                )
            } catch {
                appendAssistantMessage("Ошибка LLM: \(error.localizedDescription)")
                return
            }

            let rawResponse = dispatchResponse.message.content
            let action = parseAction(from: rawResponse)
            appendInternalMessage("⚙️ Диспетчер [итерация \(iteration + 1)] \(actionLabel(action))", response: dispatchResponse)

            switch action {
            case .call(let toolName, let args):
                let mcpResult = await executeMCPCall(toolName: toolName, args: args)
                iterationContext += "\nВызов \(iteration + 1) [\(toolName)]: \(mcpResult)"
                iteration += 1
                // продолжаем цикл

            case .parallelCall(let tools):
                let results = await withTaskGroup(of: (String, String).self) { group in
                    for (name, args) in tools {
                        group.addTask { await (name, self.executeMCPCall(toolName: name, args: args)) }
                    }
                    var collected: [(String, String)] = []
                    for await pair in group { collected.append(pair) }
                    return collected
                }
                for (name, result) in results {
                    iterationContext += "\nВызов \(iteration + 1) [\(name)]: \(result)"
                }
                iteration += 1
                // продолжаем цикл

            case .chat(let reply):
                appendAssistantMessage(reply)
                return

            case .list:
                appendAssistantMessage(formatToolList(entries: allEntries))
                return

            case .schedule(let desc, let intervalSeconds):
                guard intervalSeconds >= 10 else {
                    appendAssistantMessage("Минимальный интервал — 10 секунд.")
                    return
                }
                let task = ScheduledTask(id: UUID(), description: desc, intervalSeconds: intervalSeconds, createdAt: Date())
                scheduledTasks.append(task)
                saveScheduledTasks()
                startTimerTask(for: task)
                let num = scheduledTasks.count
                appendAssistantMessage("✅ Задача №\(num) «\(desc)» запущена каждые \(intervalSeconds) с.\nСкажите «отмени задачу \(desc)» для остановки.")
                return

            case .cancelTask(let query):
                if let match = scheduledTasks.first(where: { $0.description.localizedCaseInsensitiveContains(query) }) {
                    cancelTimerTask(id: match.id)
                    appendAssistantMessage("Задача «\(match.description)» отменена.")
                } else {
                    let names = scheduledTasks.map { "«\($0.description)»" }.joined(separator: ", ")
                    appendAssistantMessage("Задача не найдена. Активные: \(names.isEmpty ? "нет" : names)")
                }
                return

            case .cancelAllTasks:
                cancelAllTimerTasks()
                appendAssistantMessage("Все плановые задачи отменены.")
                return

            case .listTasks:
                if scheduledTasks.isEmpty {
                    appendAssistantMessage("Нет активных плановых задач.")
                } else {
                    let list = scheduledTasks.enumerated().map { i, t in
                        "№\(i+1). «\(t.description)» — каждые \(t.intervalSeconds) с"
                    }.joined(separator: "\n")
                    appendAssistantMessage("Активные задачи (\(scheduledTasks.count)):\n\(list)")
                }
                return

            case .unknown:
                appendAssistantMessage(rawResponse)
                return
            }
        }

        // Достигли maxIterations без "chat" — просим LLM подвести итог
        do {
            let finalResponse = try await sendMessage.execute(
                systemPrompt: "Ты помощник. Подведи итог выполненных действий и дай финальный ответ пользователю.",
                userMessage: "Вопрос: \(text)\n\nРезультаты инструментов:\(iterationContext)",
                tools: [],
                temperature: 0.7,
                maxTokens: 2000,
                stopWords: nil
            )
            appendAssistantMessage(finalResponse.message.content, response: finalResponse)
        } catch {
            appendAssistantMessage("Ошибка при формировании итогового ответа: \(error.localizedDescription)")
        }
    }

    override func clearConversation() {
        cancelAllTimerTasks()
        try? FileManager.default.removeItem(at: tasksFileURL)
        super.clearConversation()
    }

    // MARK: - Timer task management

    private func startTimerTask(for task: ScheduledTask) {
        let timerTask = Task { [weak self] in
            let ns = UInt64(task.intervalSeconds) * 1_000_000_000
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled, let self else { break }
                await self.executeTimerFire(task: task)
            }
        }
        timerTasks[task.id] = timerTask
    }

    private func cancelTimerTask(id: UUID) {
        timerTasks[id]?.cancel()
        timerTasks.removeValue(forKey: id)
        scheduledTasks.removeAll { $0.id == id }
        saveScheduledTasks()
    }

    private func cancelAllTimerTasks() {
        timerTasks.values.forEach { $0.cancel() }
        timerTasks.removeAll()
        scheduledTasks.removeAll()
        saveScheduledTasks()
    }

    private func executeTimerFire(task: ScheduledTask) async {
        guard scheduledTasks.contains(where: { $0.id == task.id }) else { return }
        appendInternalMessage("⚙️ Плановая задача: \(task.description)")

        let allEntries = await fetchAllTools()
        let systemPrompt = buildSystemPrompt(entries: allEntries)

        guard let dispatchResponse = try? await sendMessage.execute(
            systemPrompt: systemPrompt,
            userMessage: "Выполни задачу: \(task.description)",
            tools: [], temperature: 0.2, maxTokens: 500, stopWords: nil
        ) else {
            appendAssistantMessage("⏱ Ошибка выполнения задачи «\(task.description)»")
            fireBackgroundPublisher()
            return
        }
        appendInternalMessage("⚙️ Диспетчер (таймер)", response: dispatchResponse)

        let action = parseAction(from: dispatchResponse.message.content)
        switch action {
        case .list:
            appendAssistantMessage(formatToolList(entries: allEntries))
        case .call(let toolName, let args):
            let reply = await executeCallAction(toolName: toolName, args: args, originalText: task.description, allEntries: allEntries)
            appendAssistantMessage("⏱ \(task.description): \(reply)")
        case .chat(let reply):
            appendAssistantMessage("⏱ \(task.description): \(reply)")
        default:
            appendAssistantMessage("⏱ Задача «\(task.description)» выполнена")
        }

        fireBackgroundPublisher()
    }

    private func fireBackgroundPublisher() {
        Task { @MainActor [weak self] in
            self?.backgroundMessageSubject.send()
        }
    }

    // MARK: - Persistence

    private func saveScheduledTasks() {
        let data = try? JSONEncoder().encode(scheduledTasks)
        try? data?.write(to: tasksFileURL, options: .atomic)
    }

    private func loadScheduledTasks() {
        guard let data = try? Data(contentsOf: tasksFileURL),
              let tasks = try? JSONDecoder().decode([ScheduledTask].self, from: data)
        else { return }
        scheduledTasks = tasks
        tasks.forEach { startTimerTask(for: $0) }
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

    // MARK: - Shared call action logic

    /// Выполняет MCP-инструмент и возвращает сырой результат. Используется в агентном цикле.
    private func executeMCPCall(
        toolName: String,
        args: [String: AnyCodableValue]
    ) async -> String {
        guard let routing = toolRegistry[toolName] else {
            return "Инструмент «\(toolName)» не найден."
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

        return mcpResult
    }

    private func executeCallAction(
        toolName: String,
        args: [String: AnyCodableValue],
        originalText: String,
        allEntries: [(tool: MCPTool, server: MCPServer)]
    ) async -> String {
        guard let routing = toolRegistry[toolName] else {
            return "Инструмент «\(toolName)» не найден ни на одном из MCP-серверов."
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

        do {
            let finalResponse = try await sendMessage.execute(
                systemPrompt: "Ты помощник. Пользователь задал вопрос, ты вызвал инструмент \(toolName) [\(routing.label)] и получил результат. Ответь пользователю на основе этих данных на том же языке, что и вопрос.",
                userMessage: "Вопрос: \(originalText)\n\nРезультат инструмента \(toolName):\n\(mcpResult)",
                tools: [],
                temperature: 0.7,
                maxTokens: 1000,
                stopWords: nil
            )
            appendInternalMessage("⚙️ Синтез ответа [\(toolName)]", response: finalResponse)
            return finalResponse.message.content
        } catch {
            return mcpResult
        }
    }

    // MARK: - Private helpers

    private func appendInternalMessage(_ content: String, response: AgentResponse? = nil) {
        conversation.addMessage(Message(
            role: .summaryUsage,
            content: content,
            modelName: currentModelName,
            promptTokens: response?.usage?.promptTokens,
            completionTokens: response?.usage?.completionTokens
        ))
        persistence.save(conversation, forKey: agentConversationId.uuidString)
    }

    private func appendAssistantMessage(_ content: String, response: AgentResponse? = nil) {
        conversation.addMessage(Message(
            role: .assistant,
            content: content,
            modelName: currentModelName,
            promptTokens: response?.usage?.promptTokens,
            completionTokens: response?.usage?.completionTokens
        ))
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

    private func buildDispatchMessage(currentText: String, mcpContext: String = "") -> String {
        let history = conversation.messages
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(5)
        var parts: [String] = []
        if !history.isEmpty {
            let historyLines = history.map { msg in
                let role = msg.role == .user ? "Пользователь" : "Ассистент"
                return "\(role): \(msg.content)"
            }.joined(separator: "\n")
            parts.append("Контекст предыдущих сообщений:\n\(historyLines)")
        }
        parts.append("Текущий запрос: \(currentText)")
        if !mcpContext.isEmpty {
            parts.append("Результаты уже выполненных инструментов:\(mcpContext)\n\nНа основе этих данных реши: нужен ли ещё один вызов инструмента, или достаточно данных для ответа пользователю через {\"action\":\"chat\",\"reply\":\"...\"}?")
        }
        return parts.joined(separator: "\n\n")
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

        Ты можешь вызывать инструменты последовательно. После каждого вызова ты получишь результат и можешь решить вызвать ещё один инструмент или дать итоговый ответ пользователю через {"action":"chat","reply":"..."}. Возвращай "chat" когда у тебя достаточно данных для ответа.

        При зависимых вызовах (результат одного нужен для следующего) вызывай инструменты последовательно: каждый раз возвращай {"action":"call",...}, получай результат, используй числовые/строковые значения из него в следующем вызове.

        Проанализируй запрос пользователя и верни СТРОГО один из JSON-форматов (без комментариев, без markdown):

        1. Показать список инструментов:
           {"action":"list"}

        2. Вызвать инструмент:
           {"action":"call","tool":"имя_инструмента","args":{"параметр":"значение"}}

        3. Ответить текстом (если запрос не связан с инструментами или данных уже достаточно):
           {"action":"chat","reply":"твой ответ"}

        4. Запланировать периодическую задачу (минимальный интервал — 10 секунд):
           {"action":"schedule","description":"краткое описание задачи","intervalSeconds":30}

        5. Отменить задачу по описанию:
           {"action":"cancel_task","description":"краткое описание"}

        6. Отменить все задачи:
           {"action":"cancel_all_tasks"}

        7. Показать список задач:
           {"action":"list_tasks"}

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

    private func describeValue(_ v: AnyCodableValue) -> String {
        switch v {
        case .string(let s):
            let truncated = String(s.prefix(60))
            return truncated.count < s.count ? "\"\(truncated)…\"" : "\"\(truncated)\""
        case .int(let n):    return "\(n)"
        case .double(let d): return String(format: "%.2f", d)
        case .bool(let b):   return b ? "true" : "false"
        case .array(let a):  return "[\(a.count) эл.]"
        case .object:        return "{…}"
        case .null:          return "null"
        }
    }

    private func actionLabel(_ action: LLMAction) -> String {
        switch action {
        case .call(let tool, let args):
            let argsStr = args.isEmpty ? "" : "(\(args.map { "\($0.key): \(describeValue($0.value))" }.joined(separator: ", ")))"
            return "→ call: \(tool)\(argsStr)"
        case .parallelCall(let tools):
            return "→ parallel: \(tools.map(\.name).joined(separator: ", "))"
        case .chat(let reply):
            let preview = String(reply.prefix(80))
            return "→ chat: «\(preview)\(reply.count > 80 ? "…" : "")»"
        case .list:
            return "→ список инструментов"
        case .schedule(let desc, let interval):
            return "→ задача: «\(desc)» (каждые \(interval)с)"
        case .cancelTask(let desc):
            return "→ отмена: «\(desc)»"
        case .cancelAllTasks:
            return "→ отмена всех задач"
        case .listTasks:
            return "→ список задач"
        case .unknown:
            return "→ неизвестное действие"
        }
    }

    private enum LLMAction {
        case list
        case call(tool: String, args: [String: AnyCodableValue])
        case parallelCall(tools: [(name: String, args: [String: AnyCodableValue])])
        case chat(reply: String)
        case schedule(description: String, intervalSeconds: Int)
        case cancelTask(description: String)
        case cancelAllTasks
        case listTasks
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
            // Обработка multi_tool_use.parallel от OpenAI
            if toolName == "multi_tool_use.parallel",
               case .array(let uses) = args["tool_uses"] {
                var tools: [(name: String, args: [String: AnyCodableValue])] = []
                for use in uses {
                    guard case .object(let useDict) = use,
                          case .string(let recipientName) = useDict["recipient_name"] else { continue }
                    var toolArgs: [String: AnyCodableValue] = [:]
                    if case .object(let params) = useDict["parameters"] { toolArgs = params }
                    tools.append((name: recipientName, args: toolArgs))
                }
                if !tools.isEmpty { return .parallelCall(tools: tools) }
            }
            return .call(tool: toolName, args: args)

        case "chat":
            if case .string(let reply) = obj["reply"] { return .chat(reply: reply) }
            return nil

        case "schedule":
            guard case .string(let desc) = obj["description"] else { return nil }
            let interval: Int
            switch obj["intervalSeconds"] {
            case .int(let i): interval = i
            case .double(let d): interval = Int(d)
            default: return nil
            }
            return .schedule(description: desc, intervalSeconds: interval)

        case "cancel_task":
            if case .string(let desc) = obj["description"] { return .cancelTask(description: desc) }
            return nil

        case "cancel_all_tasks":
            return .cancelAllTasks

        case "list_tasks":
            return .listTasks

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
