//
//  TaskStateMachineAgent.swift
//  AI Advent Challenge
//

import Foundation

// MARK: - State types

enum TaskPhase: String, Codable {
    case idle, planning, execution, validation, done
}

struct TaskStep: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var description: String
    var expectedAction: String
    var isCompleted: Bool = false
    var completionNote: String? = nil
}

struct TaskState: Codable {
    var phase: TaskPhase = .idle
    var taskTitle: String? = nil
    var taskDescription: String? = nil
    var steps: [TaskStep] = []
    var currentStepIndex: Int = 0
    var isPaused: Bool = false
    var pauseNote: String? = nil
}

struct Invariant: Codable, Identifiable {
    var id: UUID = UUID()
    var text: String
}

// MARK: - Transitions

private enum TaskTransition {
    case startTask
    case confirmPlan, revisePlan, cancelTask
    case completeStep, pauseTask, resumeTask, editPlan
    case passValidation, failValidation
    case startNewTask
}

// MARK: - Agent

final class TaskStateMachineAgent: BaseAgent {

    // MARK: - Stored properties

    private let agentConversationId: UUID
    private var taskState: TaskState
    private let taskStateFileURL: URL
    private var invariants: [Invariant] = []
    private let invariantsFileURL: URL

    // MARK: - Agent metadata

    override var name: String { "Менеджер задач" }
    override var icon: String { "checklist" }
    override var description: String { "Ведёт задачи через фазы: планирование → выполнение → валидация → готово. Поддерживает паузу." }

    // MARK: - Init

    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        conversationId: UUID
    ) {
        self.agentConversationId = conversationId
        self.taskState = TaskState()

        let appSupport = FileManager.default.appSupportDirectory
        self.taskStateFileURL = appSupport
            .appendingPathComponent("AgentState/\(conversationId.uuidString)_task_state.json")
        self.invariantsFileURL = appSupport
            .appendingPathComponent("AgentState/\(conversationId.uuidString)_invariants.json")

        let systemPrompt = """
        Ты — менеджер задач, помогающий пользователю достигать целей пошагово. \
        Ты разбиваешь задачи на конкретные шаги, ведёшь через каждый шаг и оцениваешь результаты. \
        После паузы ты не повторяешь весь план — только напоминаешь текущий шаг. \
        Будь конкретным и кратким.
        """

        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: systemPrompt,
            conversationId: conversationId
        )

        self.taskState = loadTaskState() ?? TaskState()
        self.invariants = loadInvariants()

        let hasNonSystemMessages = conversation.messages.contains { $0.role != .system }
        if !hasNonSystemMessages {
            addWelcomeMessage()
        }
    }

    // MARK: - send

    override func send(_ text: String) async throws {
        // Invariant commands (work in any phase)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "инварианты" {
            appendAndSaveManual(userText: text, assistantText: buildInvariantsList())
            return
        }
        if trimmed.lowercased().hasPrefix("инвариант: ") {
            let invariantText = String(trimmed.dropFirst("инвариант: ".count))
            invariants.append(Invariant(text: invariantText))
            saveInvariants()
            appendAndSaveManual(userText: text, assistantText: "✅ Инвариант добавлен: «\(invariantText)»\n\nВсего инвариантов: \(invariants.count).")
            return
        }
        if trimmed.lowercased().hasPrefix("удалить инвариант "),
           let n = Int(trimmed.dropFirst("удалить инвариант ".count)), n >= 1, n <= invariants.count {
            let removed = invariants.remove(at: n - 1)
            saveInvariants()
            appendAndSaveManual(userText: text, assistantText: "🗑️ Инвариант удалён: «\(removed.text)».")
            return
        }
        if trimmed.lowercased() == "очистить инварианты" {
            invariants.removeAll()
            saveInvariants()
            appendAndSaveManual(userText: text, assistantText: "🗑️ Все инварианты очищены.")
            return
        }

        // Quick keyword check: block pause in non-execution phases
        let lowerText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isPauseKeyword = ["пауза", "pause", "стоп", "перерыв"].contains(lowerText)
        if isPauseKeyword && taskState.phase != .execution {
            appendAndSaveManual(userText: text, assistantText: "Пауза возможна только во время выполнения шагов.")
            return
        }

        switch taskState.phase {
        case .idle:
            try await handleIdlePhase(text)
        case .planning:
            try await handlePlanningPhase(text)
        case .execution:
            if taskState.isPaused {
                try await handleResumePhase(text)
            } else {
                try await handleExecutionPhase(text)
            }
        case .validation:
            try await handleValidationPhase(text)
        case .done:
            handleDonePhase(text)
        }
    }

    // MARK: - clearConversation

    override func clearConversation() {
        super.clearConversation()
        taskState = TaskState()
        saveTaskState()
        addWelcomeMessage()
    }

    // MARK: - State machine

    private func canApply(_ t: TaskTransition) -> Bool {
        switch t {
        case .startTask:      return taskState.phase == .idle
        case .confirmPlan:    return taskState.phase == .planning
        case .revisePlan:     return taskState.phase == .planning
        case .cancelTask:     return taskState.phase == .planning || taskState.phase == .execution
        case .completeStep:   return taskState.phase == .execution && !taskState.isPaused
        case .pauseTask:      return taskState.phase == .execution && !taskState.isPaused
        case .resumeTask:     return taskState.phase == .execution && taskState.isPaused
        case .editPlan:       return taskState.phase == .execution
        case .passValidation: return taskState.phase == .validation
        case .failValidation: return taskState.phase == .validation
        case .startNewTask:   return taskState.phase == .done
        }
    }

    private func apply(_ t: TaskTransition) {
        guard canApply(t) else { return }
        switch t {
        case .startTask:
            taskState.phase = .planning
        case .confirmPlan:
            taskState.phase = .execution
            taskState.currentStepIndex = 0
            taskState.isPaused = false
        case .revisePlan:
            taskState.steps = []
        case .cancelTask:
            taskState = TaskState()
        case .completeStep:
            taskState.steps[taskState.currentStepIndex].isCompleted = true
            taskState.currentStepIndex += 1
            if taskState.currentStepIndex >= taskState.steps.count {
                taskState.phase = .validation
            }
        case .pauseTask:
            taskState.isPaused = true
        case .resumeTask:
            taskState.isPaused = false
        case .editPlan:
            taskState.phase = .planning
            taskState.steps = []
        case .passValidation:
            taskState.phase = .done
        case .failValidation:
            taskState.phase = .execution
        case .startNewTask:
            taskState = TaskState()
        }
        saveTaskState()
    }

    // MARK: - Phase handlers

    private func handleIdlePhase(_ text: String) async throws {
        if !invariants.isEmpty {
            if let violation = await checkInvariantViolation(text) {
                appendAndSaveManual(
                    userText: text,
                    assistantText: "⛔ Задача нарушает инвариант.\n\n\(violation)\n\nПредложи другую задачу или скорректируй инварианты."
                )
                return
            }
        }

        let steps = await decomposeTask(text)
        guard !steps.isEmpty else {
            appendAndSaveManual(
                userText: text,
                assistantText: "Не удалось разбить задачу на шаги. Опишите подробнее — что именно нужно сделать?"
            )
            return
        }
        taskState.taskDescription = text
        taskState.taskTitle = String(text.prefix(60))
        taskState.steps = steps
        apply(.startTask) // idle → planning, saves

        let response = """
        Разбиваю на шаги...

        📋 ПЛАН: «\(taskState.taskTitle ?? text)»
        \(buildPlanText(steps: steps))

        Подтверждаешь план? (да / скорректировать / отмена)
        """
        appendAndSaveManual(userText: text, assistantText: response)
    }

    private func handlePlanningPhase(_ text: String) async throws {
        let intent = await detectPlanConfirmation(text)
        switch intent {
        case "confirm":
            apply(.confirmPlan) // planning → execution
            let step = taskState.steps[0]
            let response = """
            ▶️ Фаза: ВЫПОЛНЕНИЕ | Шаг 1/\(taskState.steps.count)
            📌 \(step.title)
            \(step.description)

            Ожидаемое действие: \(step.expectedAction)
            """
            appendAndSaveManual(userText: text, assistantText: response)

        case "cancel":
            apply(.cancelTask) // planning → idle
            appendAndSaveManual(
                userText: text,
                assistantText: "Задача отменена. Опишите новую задачу когда будете готовы."
            )

        default: // "revise"
            let revisedSteps = await decomposeTask(text, context: taskState.taskDescription)
            if !revisedSteps.isEmpty {
                taskState.steps = revisedSteps
                saveTaskState()
                let response = "Обновлённый план:\n\n\(buildPlanText(steps: revisedSteps))\n\nПодтверждаешь? (да / скорректировать / отмена)"
                appendAndSaveManual(userText: text, assistantText: response)
            } else {
                let response = "Текущий план:\n\n\(buildPlanText(steps: taskState.steps))\n\nПодтверждаешь? (да / скорректировать / отмена)"
                appendAndSaveManual(userText: text, assistantText: response)
            }
        }
    }

    private func handleExecutionPhase(_ text: String) async throws {
        // Check pause intent first (LLM-based for semantic detection)
        if await detectPauseIntent(text) {
            apply(.pauseTask)
            let step = taskState.steps[taskState.currentStepIndex]
            let response = "⏸️ Пауза на Шаге \(taskState.currentStepIndex + 1)/\(taskState.steps.count) — «\(step.title)».\nНапиши «продолжи» когда будешь готов."
            appendAndSaveManual(userText: text, assistantText: response)
            return
        }

        // Check edit plan intent
        if await detectEditPlanIntent(text) {
            apply(.editPlan) // execution → planning
            let revisedSteps = await decomposeTask(text, context: taskState.taskDescription)
            if !revisedSteps.isEmpty {
                taskState.steps = revisedSteps
                taskState.currentStepIndex = 0
                saveTaskState()
                let response = "Пересматриваю план:\n\n\(buildPlanText(steps: revisedSteps))\n\nПодтверждаешь? (да / скорректировать / отмена)"
                appendAndSaveManual(userText: text, assistantText: response)
            } else {
                appendAndSaveManual(
                    userText: text,
                    assistantText: "Не удалось пересмотреть план. Опишите желаемые изменения конкретнее."
                )
            }
            return
        }

        let currentStep = taskState.steps[taskState.currentStepIndex]

        // Check step completion
        if await detectStepCompletion(text, step: currentStep) {
            taskState.steps[taskState.currentStepIndex].completionNote = text
            apply(.completeStep)

            if taskState.phase == .validation {
                // Last step done — show summary and auto-validate
                let summaryLines = taskState.steps.map { "✅ \($0.title)" }.joined(separator: "\n")
                let completionResponse = "Все шаги выполнены!\n\n📊 Итоги:\n\(summaryLines)\n\nОцениваю результаты..."
                appendAndSaveManual(userText: text, assistantText: completionResponse)

                let (passed, feedback) = await validateResults(
                    steps: taskState.steps,
                    taskDescription: taskState.taskDescription ?? ""
                )
                let validationResponse: String
                if passed {
                    apply(.passValidation)
                    validationResponse = "🎉 Задача завершена успешно!\n\n\(feedback)\n\nНапиши следующую задачу когда будешь готов."
                } else {
                    taskState.steps.indices.forEach {
                        taskState.steps[$0].isCompleted = false
                        taskState.steps[$0].completionNote = nil
                    }
                    taskState.currentStepIndex = 0
                    apply(.failValidation)
                    let step0 = taskState.steps[0]
                    validationResponse = "❌ Валидация не пройдена.\n\n\(feedback)\n\nВозвращаемся к Шагу 1: «\(step0.title)»\n\nОжидаемое действие: \(step0.expectedAction)"
                }
                conversation.addMessage(Message(role: .assistant, content: validationResponse))
                persistence.save(conversation, forKey: agentConversationId.uuidString)
                updateRecord()
            } else {
                let nextStep = taskState.steps[taskState.currentStepIndex]
                let response = """
                ✅ Шаг \(taskState.currentStepIndex)/\(taskState.steps.count) выполнен!

                ▶️ Фаза: ВЫПОЛНЕНИЕ | Шаг \(taskState.currentStepIndex + 1)/\(taskState.steps.count)
                📌 \(nextStep.title)
                \(nextStep.description)

                Ожидаемое действие: \(nextStep.expectedAction)
                """
                appendAndSaveManual(userText: text, assistantText: response)
            }
        } else {
            let response = "▶️ Шаг \(taskState.currentStepIndex + 1)/\(taskState.steps.count): «\(currentStep.title)»\n\nОжидаемое действие: \(currentStep.expectedAction)\n\nСообщи когда выполнишь. (или «пауза» для перерыва)"
            appendAndSaveManual(userText: text, assistantText: response)
        }
    }

    private func handleResumePhase(_ text: String) async throws {
        if await detectContinueIntent(text) {
            apply(.resumeTask)
            let step = taskState.steps[taskState.currentStepIndex]
            let response = "▶️ Продолжаем. Шаг \(taskState.currentStepIndex + 1)/\(taskState.steps.count) — «\(step.title)».\n\nОжидаемое действие: \(step.expectedAction)"
            appendAndSaveManual(userText: text, assistantText: response)
        } else {
            let step = taskState.steps[taskState.currentStepIndex]
            let response = "⏸️ Задача на паузе (Шаг \(taskState.currentStepIndex + 1): «\(step.title)»). Напиши «продолжи» чтобы продолжить."
            appendAndSaveManual(userText: text, assistantText: response)
        }
    }

    private func handleValidationPhase(_ text: String) async throws {
        // Edge case: app recovered from crash mid-validation
        let (passed, feedback) = await validateResults(
            steps: taskState.steps,
            taskDescription: taskState.taskDescription ?? ""
        )
        if passed {
            apply(.passValidation)
            appendAndSaveManual(
                userText: text,
                assistantText: "🎉 Задача завершена!\n\n\(feedback)\n\nНапиши следующую задачу."
            )
        } else {
            taskState.steps.indices.forEach {
                taskState.steps[$0].isCompleted = false
                taskState.steps[$0].completionNote = nil
            }
            taskState.currentStepIndex = 0
            apply(.failValidation)
            let step = taskState.steps[0]
            appendAndSaveManual(
                userText: text,
                assistantText: "❌ Валидация не пройдена.\n\n\(feedback)\n\nВозвращаемся к Шагу 1: «\(step.title)»\n\nОжидаемое действие: \(step.expectedAction)"
            )
        }
    }

    private func handleDonePhase(_ text: String) {
        apply(.startNewTask) // done → idle
        appendAndSaveManual(userText: text, assistantText: "Отлично! Описывай следующую задачу — разобью на шаги.")
    }

    // MARK: - LLM utilities

    private func decomposeTask(_ text: String, context: String? = nil) async -> [TaskStep] {
        let userMessage: String
        if let ctx = context {
            userMessage = "Оригинальная задача: \(ctx)\n\nКорректировка: \(text)\n\nУчти корректировку при разбивке."
        } else {
            userMessage = text
        }
        var system = """
        Разбей задачу на 3-6 конкретных выполнимых шагов.
        Ответь ТОЛЬКО валидным JSON массивом без markdown и пояснений:
        [{"title":"...","description":"...","expectedAction":"..."}]
        title: краткое название шага (до 40 символов)
        description: что делается на этом шаге (1-2 предложения)
        expectedAction: конкретное действие пользователя (1 предложение)
        """
        if !invariants.isEmpty {
            system += "\n\nОБЯЗАТЕЛЬНЫЕ ИНВАРИАНТЫ (нельзя нарушать):\n"
            system += invariants.enumerated()
                .map { "\($0.offset + 1). \($0.element.text)" }
                .joined(separator: "\n")
            system += "\nВсе шаги плана должны строго соответствовать инвариантам."
        }
        let response = try? await sendMessage.execute(
            systemPrompt: system,
            userMessage: userMessage,
            tools: [],
            temperature: 0.3,
            maxTokens: 600,
            stopWords: nil
        )
        guard let content = response?.message.content else { return [] }
        let jsonString = extractJSON(from: content)
        guard let data = jsonString.data(using: .utf8),
              let raw = try? JSONDecoder().decode([[String: String]].self, from: data) else { return [] }
        return raw.compactMap { dict -> TaskStep? in
            guard let title = dict["title"],
                  let desc = dict["description"],
                  let action = dict["expectedAction"] else { return nil }
            return TaskStep(title: title, description: desc, expectedAction: action)
        }
    }

    private func detectPauseIntent(_ text: String) async -> Bool {
        let system = """
        Определи: хочет ли пользователь сделать паузу/остановиться?
        Ключевые слова: "пауза", "стоп", "остановись", "перерыв", "pause", "stop".
        Ответь только "да" или "нет".
        """
        let response = try? await sendMessage.execute(
            systemPrompt: system, userMessage: text, tools: [], temperature: 0.0, maxTokens: 5, stopWords: nil
        )
        return response?.message.content.lowercased().contains("да") == true
    }

    private func detectContinueIntent(_ text: String) async -> Bool {
        let system = """
        Определи: хочет ли пользователь продолжить выполнение задачи после паузы?
        Ключевые слова: "продолжи", "продолжай", "давай", "погнали", "continue", "resume", "готов", "ok".
        Ответь только "да" или "нет".
        """
        let response = try? await sendMessage.execute(
            systemPrompt: system, userMessage: text, tools: [], temperature: 0.0, maxTokens: 5, stopWords: nil
        )
        return response?.message.content.lowercased().contains("да") == true
    }

    private func detectStepCompletion(_ text: String, step: TaskStep) async -> Bool {
        let system = """
        Текущий шаг задачи: «\(step.title)»
        Ожидаемое действие: \(step.expectedAction)

        Определи: сообщает ли пользователь о выполнении этого шага?
        (слова: "готово", "сделал", "выполнил", "done", отчёт о выполнении, описание результата)
        Ответь только "да" или "нет".
        """
        let response = try? await sendMessage.execute(
            systemPrompt: system, userMessage: text, tools: [], temperature: 0.0, maxTokens: 5, stopWords: nil
        )
        return response?.message.content.lowercased().contains("да") == true
    }

    private func detectPlanConfirmation(_ text: String) async -> String {
        let system = """
        Пользователь отвечает на предложенный план задачи.
        Определи намерение — ответь ТОЛЬКО одним словом:
        confirm — подтверждает план (да, ок, согласен, поехали, начнём, готово)
        revise — хочет изменить план (нет, скорректировать, другой, изменить, добавь, убери)
        cancel — отменяет задачу (отмена, не надо, передумал, хватит)
        """
        let response = try? await sendMessage.execute(
            systemPrompt: system, userMessage: text, tools: [], temperature: 0.0, maxTokens: 10, stopWords: nil
        )
        let content = response?.message.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if content.contains("confirm") { return "confirm" }
        if content.contains("cancel") { return "cancel" }
        return "revise"
    }

    private func detectEditPlanIntent(_ text: String) async -> Bool {
        let system = """
        Определи: явно ли просит пользователь переделать/пересмотреть план задачи?
        (НЕ обычный прогресс по шагу, а именно переделать весь план)
        Ключевые слова: "переделай план", "пересмотри план", "другой план", "изменить план".
        Ответь только "да" или "нет".
        """
        let response = try? await sendMessage.execute(
            systemPrompt: system, userMessage: text, tools: [], temperature: 0.0, maxTokens: 5, stopWords: nil
        )
        return response?.message.content.lowercased().contains("да") == true
    }

    private func validateResults(steps: [TaskStep], taskDescription: String) async -> (passed: Bool, feedback: String) {
        let completedList = steps.map { step -> String in
            let note = step.completionNote.map { ": \(String($0.prefix(80)))" } ?? ""
            return "✅ \(step.title)\(note)"
        }.joined(separator: "\n")
        let system = """
        Оцени выполнение задачи.
        Задача: \(taskDescription)
        Выполненные шаги:
        \(completedList)

        Ответь строго в формате:
        RESULT: pass
        FEEDBACK: краткий отзыв
        или:
        RESULT: fail
        FEEDBACK: что нужно доработать (1-2 предложения)
        """
        let response = try? await sendMessage.execute(
            systemPrompt: system,
            userMessage: "Оцени выполнение.",
            tools: [],
            temperature: 0.2,
            maxTokens: 120,
            stopWords: nil
        )
        guard let content = response?.message.content else { return (true, "Все шаги выполнены.") }
        let passed = content.lowercased().contains("result: pass")
        let feedbackLine = content.components(separatedBy: "\n")
            .first { $0.lowercased().hasPrefix("feedback:") }
        let feedback = feedbackLine?
            .replacingOccurrences(of: "FEEDBACK:", with: "")
            .replacingOccurrences(of: "feedback:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Оценка завершена."
        return (passed, feedback)
    }

    // MARK: - Helpers

    private func buildPlanText(steps: [TaskStep]) -> String {
        steps.enumerated().map { i, step in
            "Шаг \(i + 1): \(step.title)\n  \(step.description)"
        }.joined(separator: "\n")
    }

    private func extractJSON(from text: String) -> String {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]") else { return text }
        return String(text[start...end])
    }

    private func addWelcomeMessage() {
        let welcome = """
        👋 Привет! Я — менеджер задач.

        Опиши задачу, которую хочешь выполнить — я разобью её на конкретные шаги и проведу через каждый.

        Поддерживаю паузу: пиши «пауза» чтобы остановиться, «продолжи» — чтобы возобновить.
        Поддерживаю инварианты: пиши «инвариант: <правило>» чтобы задать ограничение.
        """
        conversation.addMessage(Message(role: .assistant, content: welcome))
        persistence.save(conversation, forKey: agentConversationId.uuidString)
    }

    private func appendAndSaveManual(userText: String, assistantText: String) {
        conversation.addMessage(Message(role: .user, content: userText))
        if !assistantText.isEmpty {
            conversation.addMessage(Message(role: .assistant, content: assistantText))
        }
        persistence.save(conversation, forKey: agentConversationId.uuidString)
        updateRecord()
    }

    private func updateRecord() {
        let firstUser = conversation.messages.first(where: { $0.role == .user })?.content
        let lastMsg = conversation.messages.last(where: { $0.role == .user || $0.role == .assistant })
        persistence.updateRecord(
            id: agentConversationId,
            firstUserMessage: firstUser.map { String($0.prefix(40)) },
            lastPreview: lastMsg.map { String($0.content.prefix(80)) },
            lastDate: lastMsg?.timestamp
        )
    }

    // MARK: - Invariant helpers

    private func checkInvariantViolation(_ text: String) async -> String? {
        let invariantList = invariants.enumerated()
            .map { "\($0.offset + 1). \($0.element.text)" }
            .joined(separator: "\n")
        let system = """
        Проверь: нарушает ли следующий запрос пользователя хотя бы один из перечисленных инвариантов?

        Инварианты:
        \(invariantList)

        Ответь строго в формате:
        VIOLATION: yes
        REASON: объяснение какой инвариант нарушен и почему (1-2 предложения)
        или:
        VIOLATION: no
        """
        let response = try? await sendMessage.execute(
            systemPrompt: system, userMessage: text, tools: [], temperature: 0.0, maxTokens: 100, stopWords: nil
        )
        guard let content = response?.message.content else { return nil }
        guard content.lowercased().contains("violation: yes") else { return nil }
        let reasonLine = content.components(separatedBy: "\n")
            .first { $0.lowercased().hasPrefix("reason:") }
        return reasonLine?
            .replacingOccurrences(of: "REASON:", with: "")
            .replacingOccurrences(of: "reason:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Запрос нарушает установленные инварианты."
    }

    private func buildInvariantsList() -> String {
        guard !invariants.isEmpty else {
            return "📋 Инварианты не установлены.\n\nДобавь: «инвариант: <правило>»"
        }
        let list = invariants.enumerated()
            .map { "\($0.offset + 1). \($0.element.text)" }
            .joined(separator: "\n")
        return "📋 ИНВАРИАНТЫ (\(invariants.count)):\n\(list)\n\nДобавить: «инвариант: <правило>»\nУдалить: «удалить инвариант N»"
    }

    private func loadInvariants() -> [Invariant] {
        guard let data = try? Data(contentsOf: invariantsFileURL),
              let inv = try? JSONDecoder().decode([Invariant].self, from: data) else { return [] }
        return inv
    }

    private func saveInvariants() {
        if let data = try? JSONEncoder().encode(invariants) {
            try? data.write(to: invariantsFileURL, options: .atomic)
        }
    }

    // MARK: - Task state persistence

    private func loadTaskState() -> TaskState? {
        guard let data = try? Data(contentsOf: taskStateFileURL),
              let state = try? JSONDecoder().decode(TaskState.self, from: data) else { return nil }
        return state
    }

    private func saveTaskState() {
        if let data = try? JSONEncoder().encode(taskState) {
            try? data.write(to: taskStateFileURL, options: .atomic)
        }
    }
}
