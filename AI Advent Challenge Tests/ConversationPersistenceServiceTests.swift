import XCTest
@testable import AI_Advent_Challenge

// Unit-тесты для ConversationPersistenceService — save/load/delete, без сети.

final class ConversationPersistenceServiceTests: XCTestCase {

    private var sut: ConversationPersistenceService!

    override func setUp() {
        super.setUp()
        sut = ConversationPersistenceService()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeConversation(messageTexts: [String]) -> Conversation {
        var conversation = Conversation(systemPrompt: "Test system prompt")
        for text in messageTexts {
            let message = Message(role: .user, content: text)
            conversation.addMessage(message)
        }
        return conversation
    }

    // MARK: - Save & Load

    func test_saveAndLoad_returnsMatchingMessageCount() {
        // Arrange
        let key = UUID().uuidString
        let original = makeConversation(messageTexts: ["Привет", "Как дела?", "Что нового?"])
        defer { sut.delete(forKey: key) }

        // Act
        sut.save(original, forKey: key)
        let loaded = sut.load(forKey: key)

        // Assert
        XCTAssertNotNil(loaded, "Загруженный Conversation не должен быть nil")
        XCTAssertEqual(loaded?.messages.count, original.messages.count,
                       "Количество сообщений должно совпадать после save/load")
    }

    func test_saveAndLoad_preservesMessageContents() {
        // Arrange
        let key = UUID().uuidString
        let userText = "Уникальное сообщение \(UUID().uuidString)"
        let original = makeConversation(messageTexts: [userText])
        defer { sut.delete(forKey: key) }

        // Act
        sut.save(original, forKey: key)
        let loaded = sut.load(forKey: key)

        // Assert
        let userMessages = loaded?.messages.filter { $0.role == .user }
        XCTAssertEqual(userMessages?.first?.content, userText,
                       "Содержимое сообщения должно сохраняться корректно")
    }

    func test_load_nonExistentKey_returnsNil() {
        // Arrange
        let key = UUID().uuidString  // случайный ключ, файл не создавался

        // Act
        let result = sut.load(forKey: key)

        // Assert
        XCTAssertNil(result, "load для несуществующего ключа должен возвращать nil")
    }

    // MARK: - Delete

    func test_delete_afterSave_loadReturnsNil() {
        // Arrange
        let key = UUID().uuidString
        let conversation = makeConversation(messageTexts: ["Сообщение для удаления"])
        sut.save(conversation, forKey: key)
        XCTAssertNotNil(sut.load(forKey: key), "Предварительное условие: файл должен существовать")

        // Act
        sut.delete(forKey: key)

        // Assert
        let result = sut.load(forKey: key)
        XCTAssertNil(result, "После delete load должен возвращать nil")
    }

    func test_delete_nonExistentKey_doesNotCrash() {
        // Arrange
        let key = UUID().uuidString  // файл никогда не создавался

        // Act & Assert — не должно быть краша
        sut.delete(forKey: key)
    }

    // MARK: - Overwrite

    func test_save_overwrite_updatesMessages() {
        // Arrange
        let key = UUID().uuidString
        let original = makeConversation(messageTexts: ["Первое"])
        defer { sut.delete(forKey: key) }

        sut.save(original, forKey: key)

        var updated = makeConversation(messageTexts: ["Первое", "Второе", "Третье"])

        // Act
        sut.save(updated, forKey: key)
        let loaded = sut.load(forKey: key)

        // Assert
        XCTAssertEqual(loaded?.messages.count, updated.messages.count,
                       "После перезаписи должно сохраниться новое количество сообщений")
    }
}
