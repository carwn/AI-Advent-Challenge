import XCTest
@testable import AI_Advent_Challenge

// Unit-тесты для BranchConversationInteractor — чистая логика ветвления, без сети.

final class BranchConversationUseCaseTests: XCTestCase {

    private var sut: BranchConversationInteractor!
    private var persistence: ConversationPersistenceService!

    override func setUp() {
        super.setUp()
        persistence = ConversationPersistenceService()
        sut = BranchConversationInteractor(persistence: persistence)
    }

    override func tearDown() {
        sut = nil
        persistence = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeOriginalRecord(title: String = "Тестовый диалог") -> ConversationRecord {
        ConversationRecord(
            id: UUID(),
            agentKey: "general_agent",
            agentName: "Универсальный ассистент",
            agentIcon: "brain",
            title: title,
            lastMessagePreview: nil,
            lastMessageDate: nil,
            createdAt: Date(),
            parentId: nil
        )
    }

    // MARK: - Tests

    func test_branch_parentId_equalsOriginalId() {
        // Arrange
        let original = makeOriginalRecord()

        // Act
        let branch = sut.branch(record: original)

        // Assert
        XCTAssertEqual(branch.parentId, original.id,
            "parentId ветки должен совпадать с id оригинального диалога")
    }

    func test_branch_id_isUnique() {
        // Arrange
        let original = makeOriginalRecord()

        // Act
        let branch = sut.branch(record: original)

        // Assert
        XCTAssertNotEqual(branch.id, original.id,
            "id ветки должен отличаться от id оригинала")
    }

    func test_branch_title_containsArrow() {
        // Arrange
        let original = makeOriginalRecord(title: "Мой диалог")

        // Act
        let branch = sut.branch(record: original)

        // Assert
        XCTAssertTrue(branch.title.contains("↳"),
            "Заголовок ветки должен содержать символ '↳', получили: '\(branch.title)'")
    }
}
