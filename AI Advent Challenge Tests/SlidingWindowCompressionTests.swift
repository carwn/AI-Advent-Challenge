import XCTest
@testable import AI_Advent_Challenge

// Unit-тесты для SlidingWindowContextCompressionPolicy — stateless, без сети.

@MainActor
final class SlidingWindowCompressionTests: XCTestCase {

    // MARK: - Helpers

    private func makeConversation(systemPrompt: String = "System", userAssistantPairs: Int) -> Conversation {
        var conv = Conversation(systemPrompt: systemPrompt)
        for i in 1...max(1, userAssistantPairs) {
            conv.addMessage(Message(role: .user, content: "User \(i)"))
            conv.addMessage(Message(role: .assistant, content: "Assistant \(i)"))
        }
        return conv
    }

    // MARK: - Window smaller than history

    func test_compress_moreMessagesThanWindow_keepsOnlyLastN() async {
        let policy = SlidingWindowContextCompressionPolicy(windowSize: 2)
        var conv = Conversation(systemPrompt: "System")
        for i in 1...5 {
            conv.addMessage(Message(role: .user, content: "User \(i)"))
            conv.addMessage(Message(role: .assistant, content: "Asst \(i)"))
        }

        let (apiConv, summaryUsage, details) = await policy.compress(conv)

        // windowSize=2 → оставляем последние 2 non-system сообщения (не пары!)
        // 1 system + 2 = 3 messages
        XCTAssertEqual(apiConv.messages.count, 3)
        XCTAssertEqual(apiConv.messages[0].role, .system)
        // последние 2 сообщения: "User 5" и "Asst 5"
        XCTAssertEqual(apiConv.messages[1].content, "User 5")
        XCTAssertEqual(apiConv.messages.last?.content, "Asst 5")
        XCTAssertNil(summaryUsage, "SlidingWindow не тратит токены на сжатие")
        XCTAssertNotNil(details, "Должны быть details о количестве отброшенных сообщений")
    }

    // MARK: - Window larger than or equal to history

    func test_compress_fewerMessagesThanWindow_keepsAll() async {
        let policy = SlidingWindowContextCompressionPolicy(windowSize: 10)
        let conv = makeConversation(systemPrompt: "System", userAssistantPairs: 3)
        // 1 system + 6 non-system messages

        let (apiConv, _, details) = await policy.compress(conv)

        XCTAssertEqual(apiConv.messages.count, 7)
        XCTAssertNil(details, "Если ничего не отброшено — details должны быть nil")
    }

    func test_compress_exactWindowSize_keepsAllNonSystem() async {
        let policy = SlidingWindowContextCompressionPolicy(windowSize: 4)
        var conv = Conversation(systemPrompt: "System")
        for i in 1...2 {
            conv.addMessage(Message(role: .user, content: "U\(i)"))
            conv.addMessage(Message(role: .assistant, content: "A\(i)"))
        }
        // 1 system + 4 non-system

        let (apiConv, _, details) = await policy.compress(conv)

        XCTAssertEqual(apiConv.messages.count, 5)
        XCTAssertNil(details)
    }

    // MARK: - System message preservation

    func test_compress_alwaysPreservesSystemMessage() async {
        let policy = SlidingWindowContextCompressionPolicy(windowSize: 2)
        var conv = Conversation(systemPrompt: "Important system prompt")
        for i in 1...5 {
            conv.addMessage(Message(role: .user, content: "Q\(i)"))
        }

        let (apiConv, _, _) = await policy.compress(conv)

        XCTAssertEqual(apiConv.messages.first?.role, .system)
        XCTAssertEqual(apiConv.messages.first?.content, "Important system prompt")
    }

    func test_compress_noSystemMessage_doesNotAddFakeSystem() async {
        let policy = SlidingWindowContextCompressionPolicy(windowSize: 3)
        var conv = Conversation(systemPrompt: "")
        conv.addMessage(Message(role: .user, content: "Hello"))
        conv.addMessage(Message(role: .assistant, content: "Hi"))

        let (apiConv, _, _) = await policy.compress(conv)

        XCTAssertFalse(apiConv.messages.contains(where: { $0.role == .system }))
    }

    // MARK: - summaryUsage messages excluded

    func test_compress_summaryUsageMessagesExcluded() async {
        let policy = SlidingWindowContextCompressionPolicy(windowSize: 5)
        var conv = Conversation(systemPrompt: "System")
        conv.addMessage(Message(role: .summaryUsage, content: "Summary block"))
        conv.addMessage(Message(role: .user, content: "Hello"))
        conv.addMessage(Message(role: .assistant, content: "Hi"))

        let (apiConv, _, _) = await policy.compress(conv)

        // summaryUsage не должен попасть в API контекст
        XCTAssertFalse(apiConv.messages.contains(where: { $0.role == .summaryUsage }))
    }

    // MARK: - Details string

    func test_compress_detailsContainsDroppedCount() async {
        let policy = SlidingWindowContextCompressionPolicy(windowSize: 2)
        var conv = Conversation(systemPrompt: "S")
        for i in 1...4 {
            conv.addMessage(Message(role: .user, content: "U\(i)"))
            conv.addMessage(Message(role: .assistant, content: "A\(i)"))
        }
        // 8 non-system messages, window=2 → dropped=6

        let (_, _, details) = await policy.compress(conv)

        XCTAssertNotNil(details)
        XCTAssertTrue(details!.contains("6"), "Details должны упоминать количество отброшенных (6), получили: \(details!)")
    }

    // MARK: - Default window size

    func test_defaultWindowSize_is5() {
        XCTAssertEqual(SlidingWindowContextCompressionPolicy.defaultWindowSize, 5)
    }

    func test_description_containsWindowSize() async {
        let policy = SlidingWindowContextCompressionPolicy(windowSize: 7)
        let desc = policy.description
        XCTAssertTrue(
            desc.contains("7"),
            "description должен содержать windowSize=7, получили: '\(desc)'"
        )
    }

    // MARK: - Reset (no-op)

    func test_reset_doesNotCrash() async {
        let policy = SlidingWindowContextCompressionPolicy(windowSize: 3)
        let conv = makeConversation(systemPrompt: "S", userAssistantPairs: 2)

        policy.reset()

        // После reset поведение должно быть идентичным
        let (apiConv, _, _) = await policy.compress(conv)
        XCTAssertEqual(apiConv.messages.first?.role, .system)
    }
}
