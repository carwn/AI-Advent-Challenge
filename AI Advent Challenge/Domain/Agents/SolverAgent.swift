//
//  SolverAgent.swift
//  AI Advent Challenge
//

import Foundation

// MARK: - State types

enum SolverPhase: String, Codable {
    case awaitingTask, clarifying, gatheringAnswers
    case analyzing, confirmingPlan, executing, validating, done
}

struct SolverStep: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var description: String
    var result: String? = nil
    var isCompleted: Bool = false
}

struct SolverState: Codable {
    var phase: SolverPhase = .awaitingTask
    var taskDescription: String = ""
    var clarificationQuestions: [String] = []
    var userAnswers: String = ""
    var llmInvariants: [String] = []
    var plan: [SolverStep] = []
    var currentStepIndex: Int = 0
    var stepResults: [String] = []
    var retryCount: Int = 0
    var globalFailCount: Int = 0
    var finalResult: String? = nil
    var succeeded: Bool? = nil
}

struct SolverInvariant: Codable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var source: String  // "user" or "llm"
}

// MARK: - Transitions

private enum SolverTransition {
    case receiveTask
    case hasQuestions
    case skipToAnalyzing
    case receiveAnswers
    case planReady
    case confirmPlan
    case revisePlan
    case cancelTask
    case allStepsDone
    case validationPassed
    case validationFailed(fromStep: Int)
    case failCompletely(reason: String)
}

// MARK: - Agent

final class SolverAgent: BaseAgent {

    // MARK: - Stored properties

    private let agentConversationId: UUID
    private let currentModelName: String?
    private var solverState: SolverState
    private let solverStateFileURL: URL
    private var userInvariants: [SolverInvariant] = []
    private let invariantsFileURL: URL

    // MARK: - Agent metadata

    override var name: String { "Автономный решатель" }
    override var icon: String { "cpu" }
    override var description: String {
        "Автономно решает задачи: уточняет вопросами, планирует, выполняет каждый шаг через LLM, валидирует результат."
    }

    // MARK: - Init

    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        conversationId: UUID,
        modelName: String? = nil
    ) {
        self.agentConversationId = conversationId
        self.currentModelName = modelName
        self.solverState = SolverState()

        let appSupport = FileManager.default.appSupportDirectory
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.solverStateFileURL = appSupport
            .appendingPathComponent("AgentState/\(conversationId.uuidString)_solver_state.json")
        self.invariantsFileURL = appSupport
            .appendingPathComponent("AgentState/\(conversationId.uuidString)_solver_invariants.json")

        let systemPrompt = """
        Ты — автономный решатель задач. \
        Ты самостоятельно выполняешь задачи через цепочку LLM-вызовов, \
        уточняешь детали вопросами, планируешь шаги и выполняешь каждый из них. \
        Будь конкретным и кратким.
        """

        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: systemPrompt,
            conversationId: conversationId
        )

        self.solverState = loadSolverState() ?? SolverState()
        self.userInvariants = loadInvariants()

        let hasNonSystemMessages = conversation.messages.contains { $0.role != .system }
        if !hasNonSystemMessages {
            addWelcomeMessage()
        }
    }

    // MARK: - clearConversation

    override func clearConversation() {
        super.clearConversation()
        solverState = SolverState()
        saveSolverState()
        addWelcomeMessage()
        // Note: invariants are NOT cleared (by design)
    }

    // MARK: - send

    override func send(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Invariant commands (any phase)
        if trimmed.lowercased() == "инварианты" {
            appendAndSaveManual(userText: text, assistantText: buildInvariantsList())
            return
        }
        if trimmed.lowercased().hasPrefix("инвариант: ") {
            let invariantText = String(trimmed.dropFirst("инвариант: ".count))
            userInvariants.append(SolverInvariant(text: invariantText, source: "user"))
            saveInvariants()
            appendAndSaveManual(
                userText: text,
                assistantText: "✅ Инвариант добавлен: «\(invariantText)»\n\nВсего инвариантов: \(userInvariants.count)."
            )
            return
        }
        if trimmed.lowercased().hasPrefix("удалить инвариант "),
           let n = Int(trimmed.dropFirst("удалить инвариант ".count)), n >= 1, n <= userInvariants.count {
            let removed = userInvariants.remove(at: n - 1)
            saveInvariants()
            appendAndSaveManual(userText: text, assistantText: "🗑️ Инвариант удалён: «\(removed.text)».")
            return
        }
        if trimmed.lowercased() == "очистить инварианты" {
            userInvariants.removeAll()
            saveInvariants()
            appendAndSaveManual(userText: text, assistantText: "🗑️ Все инварианты очищены.")
            return
        }

        switch solverState.phase {
        case .awaitingTask:
            try await handleAwaitingTask(text)
        case .clarifying:
            // Clarifying is auto — treat as new task
            try await handleAwaitingTask(text)
        case .gatheringAnswers:
            try await handleGatheringAnswers(text)
        case .analyzing:
            // Auto phase — just run analyzing with user input
            conversation.addMessage(Message(role: .user, content: text))
            persistence.save(conversation, forKey: agentConversationId.uuidString)
            await runAnalyzingInternal()
        case .confirmingPlan:
            try await handleConfirmingPlan(text)
        case .executing:
            appendAndSaveManual(userText: text, assistantText: "⚙️ Выполнение в процессе, подожди...")
        case .validating:
            appendAndSaveManual(userText: text, assistantText: "⚙️ Валидация в процессе, подожди...")
        case .done:
            handleDonePhase(text)
        }
    }

    // MARK: - Phase handlers

    private func handleAwaitingTask(_ text: String) async throws {
        // Check invariants
        if !userInvariants.isEmpty {
            if let violation = await checkInvariantViolation(text) {
                appendAndSaveManual(
                    userText: text,
                    assistantText: "⛔ Задача нарушает инвариант.\n\n\(violation)\n\nПредложи другую задачу или скорректируй инварианты."
                )
                return
            }
        }

        solverState.taskDescription = text
        apply(.receiveTask) // → clarifying

        conversation.addMessage(Message(role: .user, content: text))
        persistence.save(conversation, forKey: agentConversationId.uuidString)

        appendPhaseIndicator("Выявление вопросов и ограничений")
        appendInternal("⚙️ Анализ задачи: поиск вопросов и инвариантов")

        var questions: [String] = []
        var llmInvariants: [String] = []
        for attempt in 1...3 {
            if let ((q, i), _) = await generateClarifications(task: solverState.taskDescription, existingInvariants: userInvariants.map { $0.text }) {
                questions = q; llmInvariants = i
                break
            }
            if attempt < 3 { appendInternal("⚙️ Повтор \(attempt)/3: generateClarifications") }
        }

        // Store LLM-detected invariants
        if !llmInvariants.isEmpty {
            let newInvariants = llmInvariants.map { SolverInvariant(text: $0, source: "llm") }
            userInvariants.removeAll { $0.source == "llm" }
            userInvariants.append(contentsOf: newInvariants)
            saveInvariants()
        }

        if questions.isEmpty {
            apply(.skipToAnalyzing) // clarifying → analyzing
            appendPhaseIndicator("Анализ задачи")
            await runAnalyzingInternal()
        } else {
            solverState.clarificationQuestions = questions
            apply(.hasQuestions) // clarifying → gatheringAnswers
            saveSolverState()
            appendPhaseIndicator("Уточнение деталей")

            let questionsText = questions.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            let response = "Прежде чем начать, уточню несколько деталей:\n\n\(questionsText)\n\nОтветь на вопросы (можно одним сообщением)."
            conversation.addMessage(Message(role: .assistant, content: response))
            persistence.save(conversation, forKey: agentConversationId.uuidString)
            updateRecord()
        }
    }

    private func handleGatheringAnswers(_ text: String) async throws {
        solverState.userAnswers = text
        apply(.receiveAnswers) // gatheringAnswers → analyzing

        conversation.addMessage(Message(role: .user, content: text))
        persistence.save(conversation, forKey: agentConversationId.uuidString)

        appendPhaseIndicator("Анализ задачи")
        await runAnalyzingInternal()
    }

    private func runAnalyzingInternal(existingPlan: [SolverStep] = [], revisionComment: String = "") async {
        var plan: [SolverStep]? = nil
        var planResponse: AgentResponse? = nil
        var attempts = 0
        while attempts < 3 {
            attempts += 1
            if let (p, r) = await analyzeAndPlan(
                task: solverState.taskDescription,
                answers: solverState.userAnswers,
                invariants: userInvariants.map { $0.text },
                existingPlan: existingPlan,
                revisionComment: revisionComment
            ) {
                plan = p; planResponse = r
                break
            }
            if attempts < 3 {
                appendInternal("⚙️ Повтор \(attempts)/3: analyzeAndPlan")
            }
        }
        appendInternal("⚙️ Анализ задачи и составление плана", response: planResponse)

        guard let finalPlan = plan, !finalPlan.isEmpty else {
            solverState.phase = .awaitingTask
            saveSolverState()
            let msg = "❌ Не удалось составить план задачи. Попробуй описать задачу подробнее."
            conversation.addMessage(Message(role: .assistant, content: msg))
            persistence.save(conversation, forKey: agentConversationId.uuidString)
            updateRecord()
            return
        }

        solverState.plan = finalPlan
        solverState.stepResults = []
        solverState.currentStepIndex = 0
        apply(.planReady) // analyzing → confirmingPlan
        appendPhaseIndicator("Подтверждение плана")

        let planText = buildPlanText(steps: finalPlan)
        let response = """
        📋 ПЛАН: «\(String(solverState.taskDescription.prefix(60)))»

        \(planText)

        Подтверждаешь план? (да / скорректировать / отмена)
        """
        conversation.addMessage(Message(role: .assistant, content: response))
        persistence.save(conversation, forKey: agentConversationId.uuidString)
        updateRecord()
    }

    private func handleConfirmingPlan(_ text: String) async throws {
        conversation.addMessage(Message(role: .user, content: text))
        persistence.save(conversation, forKey: agentConversationId.uuidString)

        let (intent, intentResponse) = await detectPlanConfirmation(text)
        appendInternal("⚙️ Определение намерения", response: intentResponse)

        switch intent {
        case "confirm":
            apply(.confirmPlan) // confirmingPlan → executing
            appendPhaseIndicator("Выполнение плана")
            await runExecutingLoop()

        case "cancel":
            apply(.cancelTask) // → awaitingTask
            let msg = "Задача отменена. Опиши новую задачу когда будешь готов."
            conversation.addMessage(Message(role: .assistant, content: msg))
            persistence.save(conversation, forKey: agentConversationId.uuidString)
            updateRecord()

        default: // "revise"
            let planBeforeRevision = solverState.plan
            apply(.revisePlan) // confirmingPlan → analyzing
            solverState.taskDescription = "\(solverState.taskDescription)\n\nКорректировка: \(text)"
            saveSolverState()
            appendPhaseIndicator("Корректировка плана")
            await runAnalyzingInternal(existingPlan: planBeforeRevision, revisionComment: text)
        }
    }

    private func runExecutingLoop() async {
        let totalSteps = solverState.plan.count

        let startMsg = "▶️ Начинаю автономное выполнение (\(totalSteps) шагов)..."
        conversation.addMessage(Message(role: .assistant, content: startMsg))
        persistence.save(conversation, forKey: agentConversationId.uuidString)

        while solverState.currentStepIndex < solverState.plan.count {
            let stepIdx = solverState.currentStepIndex
            let step = solverState.plan[stepIdx]

            var stepResult: String? = nil
            var stepResponse: AgentResponse? = nil
            var retryCount = 0
            while retryCount < 3 {
                if let (result, r) = await executeStep(
                    step,
                    context: solverState.taskDescription,
                    previousResults: solverState.stepResults,
                    invariants: userInvariants.map { $0.text }
                ) {
                    stepResult = result; stepResponse = r
                    break
                }
                retryCount += 1
                if retryCount < 3 {
                    appendInternal("⚙️ Повтор \(retryCount)/3: executeStep[\(stepIdx + 1)]")
                }
            }
            appendInternal("⚙️ Шаг \(stepIdx + 1)/\(totalSteps): \(step.title)", response: stepResponse)

            guard let result = stepResult else {
                solverState.globalFailCount += 1
                saveSolverState()
                if solverState.globalFailCount >= 3 {
                    apply(.failCompletely(reason: "Не удалось выполнить шаг \(stepIdx + 1)"))
                    let failMsg = "❌ Не удалось выполнить шаг \(stepIdx + 1) после 3 попыток. Задача прервана."
                    conversation.addMessage(Message(role: .assistant, content: failMsg))
                    persistence.save(conversation, forKey: agentConversationId.uuidString)
                    updateRecord()
                    return
                }
                solverState.plan[stepIdx].isCompleted = true
                solverState.plan[stepIdx].result = "❌ Не удалось выполнить"
                solverState.stepResults.append("Шаг \(stepIdx + 1) (\(step.title)): не удалось выполнить")
                solverState.currentStepIndex += 1
                saveSolverState()
                continue
            }

            solverState.plan[stepIdx].result = result
            solverState.plan[stepIdx].isCompleted = true
            solverState.stepResults.append("Шаг \(stepIdx + 1) (\(step.title)): \(result)")
            solverState.currentStepIndex += 1
            saveSolverState()

            let stepMsg = "✅ Шаг \(stepIdx + 1)/\(totalSteps): **\(step.title)**\n\n\(result)"
            conversation.addMessage(Message(role: .assistant, content: stepMsg))
            persistence.save(conversation, forKey: agentConversationId.uuidString)
        }

        apply(.allStepsDone) // executing → validating
        appendPhaseIndicator("Валидация результатов")
        await runValidating()
    }

    private func runValidating() async {
        var validationResult: (Bool, Int?, String)? = nil
        var validationResponse: AgentResponse? = nil
        var attempts = 0
        while attempts < 3 {
            attempts += 1
            if let (b, i, s, r) = await validateResults(
                task: solverState.taskDescription,
                plan: solverState.plan,
                results: solverState.stepResults
            ) {
                validationResult = (b, i, s); validationResponse = r
                break
            }
            if attempts < 3 {
                appendInternal("⚙️ Повтор \(attempts)/3: validateResults")
            }
        }
        appendInternal("⚙️ Валидация результатов", response: validationResponse)

        let (passed, retryFromStep, feedback) = validationResult ?? (true, nil, "Все шаги выполнены.")

        if passed {
            apply(.validationPassed) // validating → done
            appendPhaseIndicator("Завершено ✓")
            let finalMsg = "🎉 Задача выполнена успешно!\n\n\(feedback)\n\nОпиши следующую задачу когда будешь готов."
            conversation.addMessage(Message(role: .assistant, content: finalMsg))
            persistence.save(conversation, forKey: agentConversationId.uuidString)
            updateRecord()
        } else {
            solverState.globalFailCount += 1
            saveSolverState()

            if solverState.globalFailCount >= 3 {
                apply(.failCompletely(reason: "Валидация не пройдена трижды"))
                let failMsg = "❌ Валидация не пройдена \(solverState.globalFailCount) раза подряд. Задача прервана.\n\n\(feedback)"
                conversation.addMessage(Message(role: .assistant, content: failMsg))
                persistence.save(conversation, forKey: agentConversationId.uuidString)
                updateRecord()
                return
            }

            let fromStep = retryFromStep ?? 0
            apply(.validationFailed(fromStep: fromStep)) // validating → executing

            for i in fromStep..<solverState.plan.count {
                solverState.plan[i].isCompleted = false
                solverState.plan[i].result = nil
            }
            if fromStep < solverState.stepResults.count {
                solverState.stepResults = Array(solverState.stepResults.prefix(fromStep))
            }
            solverState.currentStepIndex = fromStep
            saveSolverState()

            let retryMsg = "❌ Валидация не пройдена. \(feedback)\n\n↩️ Возвращаюсь к шагу \(fromStep + 1)..."
            conversation.addMessage(Message(role: .assistant, content: retryMsg))
            persistence.save(conversation, forKey: agentConversationId.uuidString)

            await runExecutingLoop()
        }
    }

    private func handleDonePhase(_ text: String) {
        solverState = SolverState()
        saveSolverState()
        appendAndSaveManual(userText: text, assistantText: "Опиши следующую задачу — я выполню её автономно.")
    }

    // MARK: - State machine

    private func canApply(_ t: SolverTransition) -> Bool {
        switch t {
        case .receiveTask:
            return solverState.phase == .awaitingTask || solverState.phase == .done
        case .hasQuestions:
            return solverState.phase == .clarifying
        case .skipToAnalyzing:
            return solverState.phase == .clarifying
        case .receiveAnswers:
            return solverState.phase == .gatheringAnswers
        case .planReady:
            return solverState.phase == .analyzing
        case .confirmPlan:
            return solverState.phase == .confirmingPlan
        case .revisePlan:
            return solverState.phase == .confirmingPlan
        case .cancelTask:
            return true
        case .allStepsDone:
            return solverState.phase == .executing
        case .validationPassed:
            return solverState.phase == .validating
        case .validationFailed:
            return solverState.phase == .validating
        case .failCompletely:
            return true
        }
    }

    private func apply(_ t: SolverTransition) {
        guard canApply(t) else { return }
        switch t {
        case .receiveTask:
            solverState.phase = .clarifying
        case .hasQuestions:
            solverState.phase = .gatheringAnswers
        case .skipToAnalyzing:
            solverState.phase = .analyzing
        case .receiveAnswers:
            solverState.phase = .analyzing
        case .planReady:
            solverState.phase = .confirmingPlan
        case .confirmPlan:
            solverState.phase = .executing
        case .revisePlan:
            solverState.phase = .analyzing
        case .cancelTask:
            solverState = SolverState()
        case .allStepsDone:
            solverState.phase = .validating
        case .validationPassed:
            solverState.phase = .done
            solverState.succeeded = true
        case .validationFailed(let fromStep):
            solverState.phase = .executing
            solverState.currentStepIndex = fromStep
        case .failCompletely(let reason):
            solverState.phase = .done
            solverState.succeeded = false
            solverState.finalResult = reason
        }
        saveSolverState()
    }

    // MARK: - LLM utilities

    private func generateClarifications(task: String, existingInvariants: [String]) async -> (([String], [String]), AgentResponse)? {
        var system = """
        Ты — аналитик задач. Твоя цель: найти неясности и скрытые ограничения в задаче пользователя.

        ШАГ 1 — ПОИСК ВОПРОСОВ.
        Задай 1–3 уточняющих вопроса, если в задаче есть хотя бы одна из ситуаций:
        - Неизвестна целевая аудитория или получатель результата
        - Не указан желаемый формат, объём или стиль вывода
        - Неясны сроки, бюджет или доступные ресурсы
        - Несколько равнозначных интерпретаций задачи
        - Отсутствуют ключевые технические детали (стек, платформа, язык)
        - Непонятен критерий успеха: как понять, что задача выполнена хорошо?
        ВАЖНО: если ответ на потенциальный вопрос уже содержится в списке инвариантов ниже — НЕ задавай этот вопрос.
        Если всё перечисленное явно указано или покрыто инвариантами — вопросов нет (пустой массив).

        ШАГ 2 — ПОИСК НОВЫХ ИНВАРИАНТОВ.
        Найди явные и неявные ограничения из задачи, которые НЕЛЬЗЯ нарушать при выполнении:
        - Технические: язык, фреймворк, платформа, совместимость
        - Стилевые: тон, формат, длина
        - Этические или контентные: что нельзя включать
        - Ресурсные: бесплатные инструменты, без регистрации, оффлайн
        - Временны́е: срок, этапность
        Занеси только НОВЫЕ ограничения, которых нет в уже известных инвариантах. Если новых нет — пустой массив.

        Выведи ТОЛЬКО валидный JSON без markdown, комментариев и пояснений:
        {"questions":["вопрос 1","вопрос 2"],"invariants":["ограничение 1"]}
        """
        if !existingInvariants.isEmpty {
            let list = existingInvariants.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            system += "\n\nУЖЕ ИЗВЕСТНЫЕ ИНВАРИАНТЫ (не дублировать, использовать как контекст для вопросов):\n\(list)"
        }
        guard let response = try? await sendMessage.execute(
            systemPrompt: system,
            userMessage: task,
            tools: [],
            temperature: 0.2,
            maxTokens: 400,
            stopWords: nil
        ) else { return nil }
        let jsonStr = extractJSONObject(from: response.message.content)
        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONDecoder().decode([String: [String]].self, from: data) else { return nil }
        return ((obj["questions"] ?? [], obj["invariants"] ?? []), response)
    }

    private func analyzeAndPlan(
        task: String,
        answers: String,
        invariants: [String],
        existingPlan: [SolverStep] = [],
        revisionComment: String = ""
    ) async -> ([SolverStep], AgentResponse)? {
        let isRevision = !existingPlan.isEmpty && !revisionComment.isEmpty
        var system = """
        \(isRevision ? "Скорректируй существующий план выполнения задачи с учётом пожелания пользователя." : "Создай детальный план выполнения задачи.")
        Ответь ТОЛЬКО валидным JSON массивом (без markdown):
        [{"title":"...","description":"..."}]
        title: название шага до 40 символов
        description: что конкретно делается на этом шаге (2-3 предложения)
        Количество шагов: 3-7.
        """
        if !invariants.isEmpty {
            system += "\n\nОБЯЗАТЕЛЬНЫЕ ИНВАРИАНТЫ:\n"
            system += invariants.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
        }

        var userMsg = "Задача: \(task)"
        if !answers.isEmpty {
            userMsg += "\n\nОтветы пользователя на уточняющие вопросы: \(answers)"
        }
        if isRevision {
            let planText = existingPlan.enumerated()
                .map { "Шаг \($0.offset + 1): \($0.element.title)\n  \($0.element.description)" }
                .joined(separator: "\n")
            userMsg += "\n\nТЕКУЩИЙ ПЛАН (нужно скорректировать):\n\(planText)"
            userMsg += "\n\nПОЖЕЛАНИЕ ПОЛЬЗОВАТЕЛЯ: \(revisionComment)"
        }

        guard let response = try? await sendMessage.execute(
            systemPrompt: system,
            userMessage: userMsg,
            tools: [],
            temperature: 0.3,
            maxTokens: 600,
            stopWords: nil
        ) else { return nil }
        let jsonStr = extractJSONArray(from: response.message.content)
        guard let data = jsonStr.data(using: .utf8),
              let raw = try? JSONDecoder().decode([[String: String]].self, from: data) else { return nil }
        let steps = raw.compactMap { dict -> SolverStep? in
            guard let title = dict["title"], let desc = dict["description"] else { return nil }
            return SolverStep(title: title, description: desc)
        }
        return steps.isEmpty ? nil : (steps, response)
    }

    private func executeStep(
        _ step: SolverStep,
        context: String,
        previousResults: [String],
        invariants: [String]
    ) async -> (String, AgentResponse)? {
        var system = """
        Ты выполняешь конкретный шаг задачи. Выдай подробный результат выполнения шага.
        Будь конкретным: если это план, создай реальный план. Если текст — напиши текст. Если анализ — проведи анализ.
        """
        if !invariants.isEmpty {
            system += "\n\nИНВАРИАНТЫ (нельзя нарушать):\n"
            system += invariants.map { "• \($0)" }.joined(separator: "\n")
        }

        var userMsg = "Задача: \(context)\n\nТекущий шаг: \(step.title)\n\(step.description)"
        if !previousResults.isEmpty {
            let prev = previousResults.suffix(3).joined(separator: "\n")
            userMsg += "\n\nВыполненные ранее шаги:\n\(prev)"
        }

        guard let response = try? await sendMessage.execute(
            systemPrompt: system,
            userMessage: userMsg,
            tools: [],
            temperature: 0.5,
            maxTokens: 800,
            stopWords: nil
        ) else { return nil }
        return (response.message.content, response)
    }

    private func validateResults(task: String, plan: [SolverStep], results: [String]) async -> (Bool, Int?, String, AgentResponse)? {
        let resultsList = results.joined(separator: "\n")
        let system = """
        Оцени выполнение задачи.
        Ответь строго в формате:
        RESULT: pass
        FEEDBACK: краткая оценка
        или:
        RESULT: fail
        FEEDBACK: что именно не так (1-2 предложения)
        RETRY_STEP: N (номер шага с которого перевыполнить, начиная с 1)
        """
        let userMsg = "Задача: \(task)\n\nРезультаты шагов:\n\(resultsList)"
        guard let response = try? await sendMessage.execute(
            systemPrompt: system,
            userMessage: userMsg,
            tools: [],
            temperature: 0.2,
            maxTokens: 200,
            stopWords: nil
        ) else { return nil }
        let content = response.message.content
        let passed = content.lowercased().contains("result: pass")
        let feedbackLine = content.components(separatedBy: "\n")
            .first { $0.lowercased().hasPrefix("feedback:") }
        let feedback = feedbackLine?
            .replacingOccurrences(of: "FEEDBACK:", with: "")
            .replacingOccurrences(of: "feedback:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Оценка завершена."

        var retryFromStep: Int? = nil
        if !passed {
            let retryLine = content.components(separatedBy: "\n")
                .first { $0.lowercased().hasPrefix("retry_step:") }
            if let s = retryLine?
                .replacingOccurrences(of: "RETRY_STEP:", with: "")
                .replacingOccurrences(of: "retry_step:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
               let n = Int(s), n >= 1 {
                retryFromStep = n - 1  // Convert to 0-indexed
            }
        }

        return (passed, retryFromStep, feedback, response)
    }

    private func detectPlanConfirmation(_ text: String) async -> (String, AgentResponse?) {
        let system = """
        Пользователь отвечает на предложенный план.
        Определи намерение — ответь ТОЛЬКО одним словом:
        confirm — подтверждает план (да, ок, согласен, поехали, начнём, выполняй, приступай)
        revise — хочет изменить план (нет, скорректировать, другой, изменить, упрости, добавь, убери)
        cancel — отменяет задачу (отмена, не надо, передумал, хватит)
        """
        let response = try? await sendMessage.execute(
            systemPrompt: system, userMessage: text, tools: [], temperature: 0.0, maxTokens: 10, stopWords: nil
        )
        let content = response?.message.content.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if content.contains("confirm") { return ("confirm", response) }
        if content.contains("cancel") { return ("cancel", response) }
        return ("revise", response)
    }

    private func checkInvariantViolation(_ text: String) async -> String? {
        let invariantList = userInvariants.enumerated()
            .map { "\($0.offset + 1). \($0.element.text)" }
            .joined(separator: "\n")
        let system = """
        Проверь: нарушает ли следующий запрос пользователя хотя бы один из перечисленных инвариантов?

        Инварианты:
        \(invariantList)

        Ответь строго в формате:
        VIOLATION: yes
        REASON: объяснение (1-2 предложения)
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

    // MARK: - Helpers

    private func buildPlanText(steps: [SolverStep]) -> String {
        steps.enumerated().map { i, step in
            "Шаг \(i + 1): \(step.title)\n  \(step.description)"
        }.joined(separator: "\n\n")
    }

    private func extractJSONArray(from text: String) -> String {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]") else { return text }
        return String(text[start...end])
    }

    private func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return text }
        return String(text[start...end])
    }

    private func addWelcomeMessage() {
        let welcome = """
        👋 Привет! Я — автономный решатель задач.

        Опиши задачу — я уточню детали вопросами, составлю план и выполню каждый шаг самостоятельно через LLM. Все внутренние действия будут видны в сером тексте.

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

    private func appendPhaseIndicator(_ label: String) {
        let msg = Message(role: .summaryUsage, content: "📍 \(label)")
        conversation.addMessage(msg)
        persistence.save(conversation, forKey: agentConversationId.uuidString)
    }

    private func appendInternal(_ label: String, response: AgentResponse? = nil) {
        let msg = Message(
            role: .summaryUsage,
            content: label,
            modelName: currentModelName,
            promptTokens: response?.usage?.promptTokens,
            completionTokens: response?.usage?.completionTokens
        )
        conversation.addMessage(msg)
        persistence.save(conversation, forKey: agentConversationId.uuidString)
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

    // MARK: - Persistence

    private func loadSolverState() -> SolverState? {
        guard let data = try? Data(contentsOf: solverStateFileURL),
              let state = try? JSONDecoder().decode(SolverState.self, from: data) else { return nil }
        return state
    }

    private func saveSolverState() {
        if let data = try? JSONEncoder().encode(solverState) {
            try? data.write(to: solverStateFileURL, options: .atomic)
        }
    }

    private func loadInvariants() -> [SolverInvariant] {
        guard let data = try? Data(contentsOf: invariantsFileURL),
              let inv = try? JSONDecoder().decode([SolverInvariant].self, from: data) else { return [] }
        return inv
    }

    private func saveInvariants() {
        if let data = try? JSONEncoder().encode(userInvariants) {
            try? data.write(to: invariantsFileURL, options: .atomic)
        }
    }

    private func buildInvariantsList() -> String {
        guard !userInvariants.isEmpty else {
            return "📋 Инварианты не установлены.\n\nДобавь: «инвариант: <правило>»"
        }
        let list = userInvariants.enumerated()
            .map { "\($0.offset + 1). [\($0.element.source)] \($0.element.text)" }
            .joined(separator: "\n")
        return "📋 ИНВАРИАНТЫ (\(userInvariants.count)):\n\(list)\n\nДобавить: «инвариант: <правило>»\nУдалить: «удалить инвариант N»"
    }
}
