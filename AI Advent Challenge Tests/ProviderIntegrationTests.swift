import XCTest
@testable import AI_Advent_Challenge

// Интеграционные тесты провайдеров.
// Требуют переменную окружения TEST_API_KEY (proxyapi.ru).
// Если ключ не задан, тест пропускается (XCTSkip).

@MainActor
final class ProviderIntegrationTests: XCTestCase {

    private let userMessage = LLMMessage(role: .user, content: "Привет")

    // MARK: - OpenAI GPT-3.5 Turbo

    func testOpenAI_gpt35Turbo_respondsToHello() async throws {
        let provider = try makeOpenAIProvider(model: "gpt-3.5-turbo")
        let response = try await provider.complete(
            messages: [userMessage],
            tools: nil,
            temperature: 0.7,
            maxTokens: 100,
            stop: nil
        )
        XCTAssertFalse(response.message.content.isEmpty, "GPT-3.5 Turbo: ответ не должен быть пустым")
    }

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
    }

    // MARK: - OpenAI GPT-4.1 Nano

    func testOpenAI_gpt41Nano_respondsToHello() async throws {
        let provider = try makeOpenAIProvider(model: "gpt-4.1-nano")
        let response = try await provider.complete(
            messages: [userMessage],
            tools: nil,
            temperature: 0.7,
            maxTokens: 100,
            stop: nil
        )
        XCTAssertFalse(response.message.content.isEmpty, "GPT-4.1 Nano: ответ не должен быть пустым")
    }

    // MARK: - OpenAI GPT-4.1

    func testOpenAI_gpt41_respondsToHello() async throws {
        let provider = try makeOpenAIProvider(model: "gpt-4.1")
        let response = try await provider.complete(
            messages: [userMessage],
            tools: nil,
            temperature: 0.7,
            maxTokens: 100,
            stop: nil
        )
        XCTAssertFalse(response.message.content.isEmpty, "GPT-4.1: ответ не должен быть пустым")
    }

    // MARK: - Gemini 2.5 Flash Lite

    func testGemini_flashLite_respondsToHello() async throws {
        let provider = try makeGeminiProvider(model: "gemini-2.5-flash-lite")
        let response = try await provider.complete(
            messages: [userMessage],
            tools: nil,
            temperature: 0.7,
            maxTokens: 100,
            stop: nil
        )
        XCTAssertFalse(response.message.content.isEmpty, "Gemini 2.5 Flash Lite: ответ не должен быть пустым")
    }

    // MARK: - Gemini 2.5 Flash

    func testGemini_flash_respondsToHello() async throws {
        let provider = try makeGeminiProvider(model: "gemini-2.5-flash")
        let response = try await provider.complete(
            messages: [userMessage],
            tools: nil,
            temperature: 0.7,
            maxTokens: 100,
            stop: nil
        )
        XCTAssertFalse(response.message.content.isEmpty, "Gemini 2.5 Flash: ответ не должен быть пустым")
    }

    // MARK: - Gemini 2.5 Pro

    func testGemini_pro_respondsToHello() async throws {
        // Thinking-модель: нужен больший бюджет токенов, чтобы мышление не съедало весь лимит
        let provider = try makeGeminiProvider(model: "gemini-2.5-pro")
        let response = try await provider.complete(
            messages: [userMessage],
            tools: nil,
            temperature: 0.7,
            maxTokens: 2000,
            stop: nil
        )
        XCTAssertFalse(response.message.content.isEmpty, "Gemini 2.5 Pro: ответ не должен быть пустым")
    }

    // MARK: - Claude Haiku 4.5

    func testAnthropic_haiku_respondsToHello() async throws {
        let provider = try makeAnthropicProvider(model: "claude-haiku-4-5")
        let response = try await provider.complete(
            messages: [userMessage],
            tools: nil,
            temperature: 0.7,
            maxTokens: 100,
            stop: nil
        )
        XCTAssertFalse(response.message.content.isEmpty, "Claude Haiku 4.5: ответ не должен быть пустым")
    }

    // MARK: - Claude Sonnet 4.5

    func testAnthropic_sonnet4_respondsToHello() async throws {
        let provider = try makeAnthropicProvider(model: "claude-sonnet-4-5")
        let response = try await provider.complete(
            messages: [userMessage],
            tools: nil,
            temperature: 0.7,
            maxTokens: 100,
            stop: nil
        )
        XCTAssertFalse(response.message.content.isEmpty, "Claude Sonnet 4.5: ответ не должен быть пустым")
    }

    // MARK: - Claude Opus 4.5

    func testAnthropic_opus45_respondsToHello() async throws {
        let provider = try makeAnthropicProvider(model: "claude-opus-4-5")
        let response = try await provider.complete(
            messages: [userMessage],
            tools: nil,
            temperature: 0.7,
            maxTokens: 100,
            stop: nil
        )
        XCTAssertFalse(response.message.content.isEmpty, "Claude Opus 4.5: ответ не должен быть пустым")
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

    private func makeGeminiProvider(model: String) throws -> GeminiProvider {
        let apiKey = try requireAPIKey()
        return GeminiProvider(modelName: model, networkClient: NetworkClient(), apiKey: apiKey)
    }

    private func makeAnthropicProvider(model: String) throws -> AnthropicProvider {
        let apiKey = try requireAPIKey()
        return AnthropicProvider(modelName: model, networkClient: NetworkClient(), apiKey: apiKey)
    }
}
