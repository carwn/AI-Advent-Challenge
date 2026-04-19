import XCTest
@testable import AI_Advent_Challenge

// Unit-тесты для доменных моделей Message, Conversation и ProviderType.

final class MessageTests: XCTestCase {

    // MARK: - Message initialization

    func test_message_defaultId_isUnique() {
        let m1 = Message(role: .user, content: "Hello")
        let m2 = Message(role: .user, content: "Hello")
        XCTAssertNotEqual(m1.id, m2.id)
    }

    func test_message_customId_isPreserved() {
        let uuid = UUID()
        let m = Message(id: uuid, role: .assistant, content: "Hi")
        XCTAssertEqual(m.id, uuid)
    }

    func test_message_roles_areCorrect() {
        XCTAssertEqual(Message(role: .user,         content: "").role, .user)
        XCTAssertEqual(Message(role: .assistant,    content: "").role, .assistant)
        XCTAssertEqual(Message(role: .system,       content: "").role, .system)
        XCTAssertEqual(Message(role: .tool,         content: "").role, .tool)
        XCTAssertEqual(Message(role: .summaryUsage, content: "").role, .summaryUsage)
    }

    func test_message_optionalFields_defaultToNil() {
        let m = Message(role: .user, content: "Test")
        XCTAssertNil(m.toolCalls)
        XCTAssertNil(m.toolCallId)
        XCTAssertNil(m.responseTime)
        XCTAssertNil(m.modelName)
        XCTAssertNil(m.promptTokens)
        XCTAssertNil(m.completionTokens)
        XCTAssertNil(m.thoughtsTokens)
    }

    func test_message_withAllFields_preservesValues() {
        let toolCall = ToolCall(
            id: "tc_1",
            type: "function",
            function: .init(name: "calculate", arguments: "{}")
        )
        let m = Message(
            role: .tool,
            content: "result",
            toolCalls: [toolCall],
            toolCallId: "tc_1",
            responseTime: 1.23,
            modelName: "gpt-4",
            promptTokens: 100,
            completionTokens: 50,
            thoughtsTokens: 25
        )
        XCTAssertEqual(m.toolCalls?.count, 1)
        XCTAssertEqual(m.toolCallId, "tc_1")
        XCTAssertEqual(m.responseTime, 1.23)
        XCTAssertEqual(m.modelName, "gpt-4")
        XCTAssertEqual(m.promptTokens, 100)
        XCTAssertEqual(m.completionTokens, 50)
        XCTAssertEqual(m.thoughtsTokens, 25)
    }

    func test_message_equatable_sameId_isEqual() {
        let uuid = UUID()
        let ts = Date(timeIntervalSince1970: 1_000_000)
        let m1 = Message(id: uuid, role: .user, content: "A", timestamp: ts)
        let m2 = Message(id: uuid, role: .user, content: "A", timestamp: ts)
        XCTAssertEqual(m1, m2)
    }

    func test_message_equatable_differentId_isNotEqual() {
        let m1 = Message(role: .user, content: "Hello")
        let m2 = Message(role: .user, content: "Hello")
        XCTAssertNotEqual(m1, m2)
    }

    // MARK: - MessageRole raw values

    func test_messageRole_rawValues() {
        XCTAssertEqual(MessageRole.system.rawValue,       "system")
        XCTAssertEqual(MessageRole.user.rawValue,         "user")
        XCTAssertEqual(MessageRole.assistant.rawValue,    "assistant")
        XCTAssertEqual(MessageRole.tool.rawValue,         "tool")
        XCTAssertEqual(MessageRole.summaryUsage.rawValue, "summaryUsage")
    }

    // MARK: - Message Codable round-trip

    func test_message_codableRoundTrip() throws {
        let original = Message(
            role: .assistant,
            content: "Hello world",
            responseTime: 0.5,
            modelName: "test-model",
            promptTokens: 10,
            completionTokens: 20
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Message.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}

// MARK: -

final class ConversationTests: XCTestCase {

    // MARK: - Init

    func test_init_withSystemPrompt_addsSystemMessage() {
        let conv = Conversation(systemPrompt: "You are helpful")
        XCTAssertEqual(conv.messages.count, 1)
        XCTAssertEqual(conv.messages[0].role, .system)
        XCTAssertEqual(conv.messages[0].content, "You are helpful")
    }

    func test_init_emptySystemPrompt_hasNoMessages() {
        let conv = Conversation(systemPrompt: "")
        XCTAssertTrue(conv.messages.isEmpty)
    }

    // MARK: - addMessage

    func test_addMessage_appendsToMessages() {
        var conv = Conversation(systemPrompt: "System")
        let msg = Message(role: .user, content: "Hello")
        conv.addMessage(msg)
        XCTAssertEqual(conv.messages.count, 2)
        XCTAssertEqual(conv.messages.last?.content, "Hello")
    }

    func test_addMessage_multipleMessages_preservesOrder() {
        var conv = Conversation(systemPrompt: "")
        conv.addMessage(Message(role: .user, content: "First"))
        conv.addMessage(Message(role: .assistant, content: "Second"))
        conv.addMessage(Message(role: .user, content: "Third"))
        XCTAssertEqual(conv.messages[0].content, "First")
        XCTAssertEqual(conv.messages[1].content, "Second")
        XCTAssertEqual(conv.messages[2].content, "Third")
    }

    // MARK: - updateMessageContent

    func test_updateMessageContent_existingId_updatesContent() {
        var conv = Conversation(systemPrompt: "")
        let msg = Message(role: .assistant, content: "Original")
        conv.addMessage(msg)

        conv.updateMessageContent(id: msg.id, content: "Updated")

        XCTAssertEqual(conv.messages.last?.content, "Updated")
        XCTAssertEqual(conv.messages.last?.id, msg.id, "ID должен остаться прежним")
        XCTAssertEqual(conv.messages.last?.role, .assistant, "Role должен остаться прежним")
    }

    func test_updateMessageContent_nonExistingId_doesNothing() {
        var conv = Conversation(systemPrompt: "System")
        conv.addMessage(Message(role: .user, content: "Hello"))
        let originalCount = conv.messages.count

        conv.updateMessageContent(id: UUID(), content: "This should not appear")

        XCTAssertEqual(conv.messages.count, originalCount)
        XCTAssertFalse(conv.messages.contains(where: { $0.content == "This should not appear" }))
    }

    func test_updateMessageContent_preservesOtherMessages() {
        var conv = Conversation(systemPrompt: "")
        let m1 = Message(role: .user, content: "First")
        let m2 = Message(role: .assistant, content: "Second")
        conv.addMessage(m1)
        conv.addMessage(m2)

        conv.updateMessageContent(id: m1.id, content: "First — updated")

        XCTAssertEqual(conv.messages[0].content, "First — updated")
        XCTAssertEqual(conv.messages[1].content, "Second", "Второе сообщение не должно измениться")
    }

    // MARK: - Codable round-trip

    func test_conversation_codableRoundTrip() throws {
        var conv = Conversation(systemPrompt: "System prompt")
        conv.addMessage(Message(role: .user, content: "Question"))
        conv.addMessage(Message(role: .assistant, content: "Answer", promptTokens: 5, completionTokens: 10))

        let data = try JSONEncoder().encode(conv)
        let decoded = try JSONDecoder().decode(Conversation.self, from: data)

        XCTAssertEqual(decoded.messages.count, conv.messages.count)
        XCTAssertEqual(decoded.messages[0].content, "System prompt")
        XCTAssertEqual(decoded.messages[2].completionTokens, 10)
    }
}

// MARK: -

final class ProviderTypeTests: XCTestCase {

    // MARK: - Total count

    func test_providerType_totalCount_is16() {
        XCTAssertEqual(ProviderType.allCases.count, 16)
    }

    // MARK: - Raw values (model identifiers)

    func test_providerType_rawValues_areCorrect() {
        XCTAssertEqual(ProviderType.gpt35Turbo.rawValue,      "gpt-3.5-turbo")
        XCTAssertEqual(ProviderType.claudeHaiku.rawValue,     "claude-haiku-4-5")
        XCTAssertEqual(ProviderType.geminiFlash.rawValue,     "gemini-2.5-flash")
        XCTAssertEqual(ProviderType.ollamaQwen35_4b.rawValue, "ollama_qwen35_4b")
    }

    // MARK: - Pricing: cloud models have non-zero prices

    func test_pricing_cloudModels_haveNonZeroOutputPrice() {
        let cloudModels: [ProviderType] = [
            .gpt35Turbo, .gpt41Nano, .gpt41Mini, .gpt41,
            .claudeHaiku, .claudeSonnet4, .claudeOpus45,
            .geminiFlashLite, .geminiFlash, .geminiPro
        ]
        for model in cloudModels {
            let pricing = model.pricingRUB
            XCTAssertGreaterThan(pricing.input,  0, "\(model.rawValue) — input price должна быть > 0")
            XCTAssertGreaterThan(pricing.output, 0, "\(model.rawValue) — output price должна быть > 0")
        }
    }

    // MARK: - Pricing: local Ollama models are free

    func test_pricing_ollamaModels_areZero() {
        let localModels: [ProviderType] = [
            .ollamaQwen35_4b, .ollamaQwen35HighTemp, .ollamaQwen35Q8,
            .ollamaQwen35Pirate, .ollamaWinQwen35_4b, .ollamaWinQwen3_14b
        ]
        for model in localModels {
            let pricing = model.pricingRUB
            XCTAssertEqual(pricing.input,  0, "\(model.rawValue) — локальная модель, input должна быть 0")
            XCTAssertEqual(pricing.output, 0, "\(model.rawValue) — локальная модель, output должна быть 0")
        }
    }

    // MARK: - Pricing ordering: more capable = more expensive (output)

    func test_pricing_gpt41_moreExpensiveThan_gpt41mini() {
        XCTAssertGreaterThan(ProviderType.gpt41.pricingRUB.output, ProviderType.gpt41Mini.pricingRUB.output)
    }

    func test_pricing_claudeOpus_moreExpensiveThan_claudeSonnet() {
        XCTAssertGreaterThan(ProviderType.claudeOpus45.pricingRUB.output, ProviderType.claudeSonnet4.pricingRUB.output)
    }

    func test_pricing_claudeSonnet_moreExpensiveThan_claudeHaiku() {
        XCTAssertGreaterThan(ProviderType.claudeSonnet4.pricingRUB.output, ProviderType.claudeHaiku.pricingRUB.output)
    }

    func test_pricing_geminiPro_moreExpensiveThan_geminiFlash() {
        XCTAssertGreaterThan(ProviderType.geminiPro.pricingRUB.output, ProviderType.geminiFlash.pricingRUB.output)
    }

    // MARK: - Display names are non-empty

    func test_displayName_allCases_areNonEmpty() {
        for model in ProviderType.allCases {
            XCTAssertFalse(model.displayName.isEmpty, "\(model.rawValue) — displayName не должен быть пустым")
        }
    }

    // MARK: - CaseIterable + RawRepresentable round-trip

    func test_providerType_rawRepresentable_roundTrip() {
        for model in ProviderType.allCases {
            let restored = ProviderType(rawValue: model.rawValue)
            XCTAssertNotNil(restored, "Не удалось восстановить \(model.rawValue) из rawValue")
            XCTAssertEqual(restored, model)
        }
    }
}
