//
//  UserProfileAgent.swift
//  AI Advent Challenge
//

import Foundation

// MARK: - Question configuration (add/edit questions here)

struct ProfileQuestion {
    let key: String            // ключ в профиле
    let displayName: String    // название в выводе профиля
    let question: String       // текст вопроса пользователю
    let validationHint: String // подсказка для LLM-валидатора
}

// MARK: - Persisted state

private struct ProfilingState: Codable {
    var currentQuestionIndex: Int = 0
    var answers: [String: String] = [:]
    var isComplete: Bool = false
    var editingKey: String? = nil  // nil = обычный режим; non-nil = ждём новое значение
}

// MARK: - Agent

final class UserProfileAgent: BaseAgent {

    // MARK: - Questions (редактируйте этот список для изменения/добавления вопросов)

    static let questions: [ProfileQuestion] = [
        ProfileQuestion(
            key: "response_style",
            displayName: "Стиль ответов",
            question: "В каком стиле вы предпочитаете получать ответы? (формально/неформально, кратко/подробно)",
            validationHint: "Ответ должен упоминать стиль общения: формальный/неформальный, краткий/подробный или другие коммуникационные предпочтения"
        ),
        ProfileQuestion(
            key: "format",
            displayName: "Формат",
            question: "Предпочтительный формат: списки, абзацы, с примерами кода?",
            validationHint: "Ответ должен упоминать формат представления информации (списки, абзацы, код, схемы и т.п.)"
        ),
        ProfileQuestion(
            key: "constraints",
            displayName: "Ограничения",
            question: "Есть темы или ограничения, которых должны придерживаться агенты?",
            validationHint: "Любой ответ об ограничениях или их отсутствии (например, 'нет ограничений') является корректным"
        ),
        ProfileQuestion(
            key: "expertise",
            displayName: "Экспертиза",
            question: "Опишите ваш уровень и область деятельности",
            validationHint: "Ответ должен упоминать профессию, область знаний или уровень опыта"
        ),
        ProfileQuestion(
            key: "language",
            displayName: "Язык",
            question: "На каком языке предпочитаете получать ответы?",
            validationHint: "Ответ должен упоминать язык или согласие использовать текущий язык"
        ),
    ]

    // MARK: - Stored properties

    /// Дублирует private conversationId из BaseAgent — единственный способ получить ID без изменения BaseAgent
    private let agentConversationId: UUID
    private let longTermMemoryStore: LongTermMemoryStore
    private var profilingState: ProfilingState
    private let profileStateFileURL: URL

    // MARK: - Agent metadata

    override var name: String { "Профайлер" }
    override var icon: String { "person.text.rectangle.fill" }
    override var description: String { "Собирает профиль предпочтений: стиль, формат, ограничения. Сохраняет в долговременную память." }
    override var temperature: Double { 0.2 }
    override var maxTokens: Int { 500 }

    // MARK: - Init

    init(
        sendMessage: any SendMessageToLMMUseCase,
        persistence: ConversationPersistenceService,
        conversationId: UUID,
        longTermMemoryStore: LongTermMemoryStore
    ) {
        self.agentConversationId = conversationId
        self.longTermMemoryStore = longTermMemoryStore
        self.profilingState = ProfilingState()

        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.profileStateFileURL = appSupport
            .appendingPathComponent("AgentState/\(conversationId.uuidString)_profile.json")

        let systemPrompt = """
        Ты — профайлер, который помогает собрать информацию о предпочтениях пользователя. \
        После завершения опроса ты — универсальный ассистент, учитывающий собранный профиль.
        """

        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: systemPrompt,
            conversationId: conversationId
        )

        self.profilingState = loadProfilingState() ?? ProfilingState()

        // Добавить приветственный вопрос только если разговор совсем новый
        let hasNonSystemMessages = conversation.messages.contains { $0.role != .system }
        if !hasNonSystemMessages && !profilingState.isComplete {
            addInitialQuestion()
        }
    }

    // MARK: - send

    override func send(_ text: String) async throws {
        // Фаза 1: сбор профиля
        if !profilingState.isComplete {
            try await handleProfilingPhase(text)
            return
        }
        // Фаза 2: ждём новое значение для редактируемого свойства
        if let key = profilingState.editingKey {
            try await handleEditingPhase(text, editingKey: key)
            return
        }
        // Фаза 3: профиль полный, обычный чат — проверяем намерение редактировать
        if let keyToEdit = await detectEditIntent(text) {
            guard let question = Self.questions.first(where: { $0.key == keyToEdit }) else {
                try await super.send(text)
                return
            }
            profilingState.editingKey = keyToEdit
            saveProfilingState()
            let current = profilingState.answers[keyToEdit].map { "Текущее значение: «\($0)»\n\n" } ?? ""
            appendAndSaveManual(
                userText: text,
                assistantText: "Хорошо, давайте обновим «\(question.displayName)».\n\n\(current)\(question.question)"
            )
        } else {
            try await super.send(text)
        }
    }

    // MARK: - clearConversation

    override func clearConversation() {
        super.clearConversation()
        profilingState = ProfilingState()
        deleteProfilingState()
        addInitialQuestion()
    }

    // MARK: - Private: phases

    private func handleProfilingPhase(_ text: String) async throws {
        let currentQuestion = Self.questions[profilingState.currentQuestionIndex]

        let valid = await validateAnswer(text, for: currentQuestion)

        let responseContent: String
        if valid {
            profilingState.answers[currentQuestion.key] = text
            profilingState.currentQuestionIndex += 1

            if profilingState.currentQuestionIndex >= Self.questions.count {
                // Все вопросы заданы — сохраняем профиль
                profilingState.isComplete = true
                saveProfilingState()
                await saveProfileToLongTermMemory()

                let lines = Self.questions.compactMap { q -> String? in
                    guard let a = profilingState.answers[q.key] else { return nil }
                    return "• \(q.displayName): \(a)"
                }
                responseContent = "Профиль собран и сохранён в долговременную память!\n\n"
                    + lines.joined(separator: "\n")
                    + "\n\nТеперь вы можете использовать Агента с тройной памятью — он автоматически учтёт ваши предпочтения."
            } else {
                saveProfilingState()
                let nextQuestion = Self.questions[profilingState.currentQuestionIndex]
                responseContent = "Отлично! \(nextQuestion.question)"
            }
        } else {
            responseContent = "Пожалуйста, ответьте на вопрос: \(currentQuestion.question)"
        }

        appendAndSaveManual(userText: text, assistantText: responseContent)
    }

    private func handleEditingPhase(_ text: String, editingKey: String) async throws {
        guard let question = Self.questions.first(where: { $0.key == editingKey }) else {
            profilingState.editingKey = nil
            saveProfilingState()
            try await super.send(text)
            return
        }
        let valid = await validateAnswer(text, for: question)
        let responseText: String
        if valid {
            profilingState.answers[editingKey] = text
            profilingState.editingKey = nil
            saveProfilingState()
            await saveProfileToLongTermMemory()
            responseText = "Готово! «\(question.displayName)» обновлено: «\(text)»\n\nПрофиль сохранён в долговременную память."
        } else {
            responseText = "Пожалуйста, ответьте на вопрос: \(question.question)"
        }
        appendAndSaveManual(userText: text, assistantText: responseText)
    }

    // MARK: - Private: edit intent detection

    private func detectEditIntent(_ text: String) async -> String? {
        let keysList = Self.questions.map { "\($0.key) (\($0.displayName))" }.joined(separator: ", ")
        let system = """
        Пользователь общается с профайлером, у которого уже собран профиль.
        Определи: хочет ли пользователь изменить конкретное свойство профиля?
        Доступные свойства: \(keysList)
        Если хочет изменить — ответь только ключом свойства (например: response_style).
        Если не хочет изменять профиль — ответь: no
        """
        let response = try? await sendMessage.execute(
            systemPrompt: system,
            userMessage: text,
            tools: [],
            temperature: 0.0,
            maxTokens: 20,
            stopWords: nil
        )
        guard let content = response?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
        return Self.questions.map(\.key).first(where: { content.contains($0) })
    }

    // MARK: - Private: helpers

    private func appendAndSaveManual(userText: String, assistantText: String) {
        conversation.addMessage(Message(role: .user, content: userText))
        conversation.addMessage(Message(role: .assistant, content: assistantText))
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

    private func addInitialQuestion() {
        guard !Self.questions.isEmpty else { return }
        let welcomeText = "Привет! Я помогу собрать ваш профиль предпочтений для персонализации ответов.\n\n\(Self.questions[0].question)"
        conversation.addMessage(Message(role: .assistant, content: welcomeText))
        persistence.save(conversation, forKey: agentConversationId.uuidString)
    }

    private func validateAnswer(_ text: String, for question: ProfileQuestion) async -> Bool {
        let system = """
        Проверь: ответил ли пользователь на вопрос по существу.
        Вопрос: "\(question.question)"
        Ожидание: \(question.validationHint)
        Ответь только "да" или "нет".
        """
        let response = try? await sendMessage.execute(
            systemPrompt: system,
            userMessage: text,
            tools: [],
            temperature: 0.0,
            maxTokens: 5,
            stopWords: nil
        )
        return response?.message.content.lowercased().contains("да") == true
    }

    private func saveProfileToLongTermMemory() async {
        let header = "=== ПРОФИЛЬ ПОЛЬЗОВАТЕЛЯ ==="
        var lines = [header]
        for q in Self.questions {
            if let a = profilingState.answers[q.key] {
                lines.append("\(q.displayName): \(a)")
            }
        }
        lines.append(String(repeating: "=", count: header.count))
        let profileText = lines.joined(separator: "\n")

        let existing = longTermMemoryStore.currentText()
        let newText: String
        if let range = existing.range(of: "=== ПРОФИЛЬ ПОЛЬЗОВАТЕЛЯ ===") {
            // Заменить существующую секцию профиля
            let before = String(existing[..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            newText = before.isEmpty ? profileText : before + "\n\n" + profileText
        } else {
            newText = existing.isEmpty ? profileText : existing + "\n\n" + profileText
        }

        await MainActor.run {
            longTermMemoryStore.text = newText
            longTermMemoryStore.save()
        }
    }

    // MARK: - Profiling state persistence

    private func loadProfilingState() -> ProfilingState? {
        guard let data = try? Data(contentsOf: profileStateFileURL),
              let state = try? JSONDecoder().decode(ProfilingState.self, from: data) else {
            return nil
        }
        return state
    }

    private func saveProfilingState() {
        if let data = try? JSONEncoder().encode(profilingState) {
            try? data.write(to: profileStateFileURL, options: .atomic)
        }
    }

    private func deleteProfilingState() {
        try? FileManager.default.removeItem(at: profileStateFileURL)
    }
}
