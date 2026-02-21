import XCTest
@testable import AI_Advent_Challenge

// Интеграционные тесты провайдеров.
// Требуют переменную окружения TEST_API_KEY (proxyapi.ru).
// Если ключ не задан, тест пропускается (XCTSkip).

@MainActor
final class ProviderIntegrationTests: XCTestCase {

    private let userMessage = Message(role: .user, content: "Привет")

    // MARK: - OpenAI GPT-4.1 Mini

    func testOpenAI_mini_respondsToHello() async throws {
        let provider = try makeOpenAIProvider(model: "gpt-4.1-mini")
        let response = try await provider.complete(
            messages: [userMessage],
            tools: nil,
            temperature: 0.7,
            maxTokens: 100,
            stop: nil
        )
        XCTAssertFalse(response.message.content.isEmpty, "GPT-4.1 Mini: ответ не должен быть пустым")
        XCTAssertEqual(response.message.role, .assistant)
    }

    // MARK: - OpenAI GPT-5.2

    func testOpenAI_gpt52_respondsToHello() async throws {
        let provider = try makeOpenAIProvider(model: "gpt-5.2")
        let response = try await provider.complete(
            messages: [userMessage],
            tools: nil,
            temperature: 0.7,
            maxTokens: 100,
            stop: nil
        )
        XCTAssertFalse(response.message.content.isEmpty, "GPT-5.2: ответ не должен быть пустым")
        XCTAssertEqual(response.message.role, .assistant)
    }

    // MARK: - Anthropic Claude

    func testAnthropic_respondsToHello() async throws {
        let apiKey = try requireAPIKey()
        let provider = AnthropicProvider(networkClient: NetworkClient(), apiKey: apiKey)
        let response = try await provider.complete(
            messages: [userMessage],
            tools: nil,
            temperature: 0.7,
            maxTokens: 100,
            stop: nil
        )
        XCTAssertFalse(response.message.content.isEmpty, "Anthropic: ответ не должен быть пустым")
        XCTAssertEqual(response.message.role, .assistant)
    }

    // MARK: - Gemini

    func testGemini_respondsToHello() async throws {
        let apiKey = try requireAPIKey()
        let provider = GeminiProvider(networkClient: NetworkClient(), apiKey: apiKey)
        let response = try await provider.complete(
            messages: [userMessage],
            tools: nil,
            temperature: 0.7,
            maxTokens: 100,
            stop: nil
        )
        XCTAssertFalse(response.message.content.isEmpty, "Gemini: ответ не должен быть пустым")
        XCTAssertEqual(response.message.role, .assistant)
    }

    // MARK: - Helpers

    private func requireAPIKey() throws -> String {
        // 1. Переменная окружения (CI / Xcode Test Plan)
        if let key = ProcessInfo.processInfo.environment["TEST_API_KEY"], !key.isEmpty {
            return key
        }
        // 2. Локальный файл рядом с тестами (gitignored)
        let secretsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Secrets.txt")
        if let key = try? String(contentsOf: secretsURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return key
        }
        throw XCTSkip("API ключ не задан. Задайте TEST_API_KEY или создайте файл AI Advent Challenge Tests/Secrets.txt")
    }

    private func makeOpenAIProvider(model: String) throws -> OpenAIProvider {
        let apiKey = try requireAPIKey()
        return OpenAIProvider(modelName: model, networkClient: NetworkClient(), apiKey: apiKey)
    }
}
