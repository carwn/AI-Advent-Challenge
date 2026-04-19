//
//  LLMProvider.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

/// Единица потокового ответа от LLM-провайдера.
///
/// Провайдер возвращает поток значений этого типа при вызове ``LLMProvider/streamComplete(messages:tools:temperature:maxTokens:stop:)``.
/// Токены reasoning-моделей приходят как ``thinking(_:)``, обычный ответ — как ``content(_:)``,
/// финальная статистика токенов — как ``usage(_:)``.
enum StreamChunk {
    /// Инкрементальный токен внутреннего размышления (reasoning), генерируемый thinking-моделями.
    case thinking(String)
    /// Инкрементальный токен финального ответа модели.
    case content(String)
    /// Финальная статистика использования токенов, отправляемая по завершении потока.
    case usage(UsageInfo)
}

/// Абстракция над LLM-провайдером (OpenAI, Anthropic, Gemini, Ollama и др.).
///
/// Каждый конкретный провайдер реализует этот протокол и предоставляет единый интерфейс
/// для отправки сообщений и получения ответов — как в блокирующем, так и в потоковом режиме.
/// ``SendMessageToLMMInteractor`` использует `LLMProvider` для выполнения запросов к LLM.
protocol LLMProvider {
    /// Идентификатор модели, используемой провайдером (например, `"gpt-4.1-mini"`, `"claude-sonnet-4-5"`).
    var modelName: String { get }

    /// Минимальный бюджет выходных токенов для моделей с thinking-режимом.
    ///
    /// Thinking-модели (например, Gemini 2.5) резервируют часть `maxOutputTokens` под reasoning.
    /// Агент применяет `max(agentMaxTokens, provider.minMaxTokens)`, чтобы гарантировать достаточный
    /// лимит для генерации ответа. Для провайдеров без thinking значение равно `0`.
    var minMaxTokens: Int { get }

    /// Поддерживает ли провайдер нативный потоковый режим (SSE).
    ///
    /// Если `true`, ``streamComplete(messages:tools:temperature:maxTokens:stop:)`` передаёт
    /// токены инкрементально по мере генерации. Если `false`, используется дефолтная реализация,
    /// которая оборачивает ``complete(messages:tools:temperature:maxTokens:stop:)`` в поток
    /// и возвращает весь ответ единовременно.
    var supportsStreaming: Bool { get }

    /// Отправляет список сообщений провайдеру и возвращает полный ответ модели.
    ///
    /// Метод выполняет один HTTP-запрос к API провайдера. Если модель поддерживает вызов
    /// инструментов и `tools` не пуст, ответ может содержать `toolCalls`, которые
    /// `SendMessageToLMMInteractor` выполнит и вернёт результаты в следующем запросе.
    ///
    /// - Parameters:
    ///   - messages: Список сообщений диалога в формате ``LLMMessage`` (system, user, assistant, tool).
    ///   - tools: Список доступных инструментов (функций), которые модель может вызвать. `nil` — без инструментов.
    ///   - temperature: Температура сэмплирования (0.0–2.0). Более высокие значения увеличивают случайность.
    ///   - maxTokens: Максимальное число токенов в ответе. `nil` — провайдер использует свой дефолт.
    ///   - stop: Список стоп-последовательностей, при обнаружении которых генерация прекращается. `nil` — без ограничений.
    /// - Returns: ``AgentResponse`` с текстом ответа, опциональным reasoning, вызовами инструментов и статистикой токенов.
    /// - Throws: ``NetworkError`` при сетевых ошибках или ошибках API провайдера.
    func complete(
        messages: [LLMMessage],
        tools: [ToolDefinition]?,
        temperature: Double,
        maxTokens: Int?,
        stop: [String]?
    ) async throws -> AgentResponse

    /// Отправляет список сообщений провайдеру и возвращает ответ в виде асинхронного потока токенов.
    ///
    /// Провайдеры с `supportsStreaming == true` передают токены инкрементально через SSE,
    /// позволяя UI отображать ответ по мере генерации. Для thinking-моделей в поток сначала
    /// приходят `.thinking`-чанки, затем `.content`-чанки, и в конце — `.usage` со статистикой.
    ///
    /// Провайдеры без нативного стриминга получают дефолтную реализацию из `extension LLMProvider`,
    /// которая вызывает ``complete(messages:tools:temperature:maxTokens:stop:)`` и эмулирует поток.
    ///
    /// - Parameters:
    ///   - messages: Список сообщений диалога в формате ``LLMMessage`` (system, user, assistant, tool).
    ///   - tools: Список доступных инструментов (функций), которые модель может вызвать. `nil` — без инструментов.
    ///   - temperature: Температура сэмплирования (0.0–2.0). Более высокие значения увеличивают случайность.
    ///   - maxTokens: Максимальное число токенов в ответе. `nil` — провайдер использует свой дефолт.
    ///   - stop: Список стоп-последовательностей, при обнаружении которых генерация прекращается. `nil` — без ограничений.
    /// - Returns: `AsyncThrowingStream<StreamChunk, Error>` — асинхронный поток чанков ``StreamChunk``.
    func streamComplete(
        messages: [LLMMessage],
        tools: [ToolDefinition]?,
        temperature: Double,
        maxTokens: Int?,
        stop: [String]?
    ) -> AsyncThrowingStream<StreamChunk, Error>
}

extension LLMProvider {
    var minMaxTokens: Int { 0 }
    var supportsStreaming: Bool { false }

    /// Дефолтная реализация потокового режима: оборачивает ``complete(messages:tools:temperature:maxTokens:stop:)`` в поток.
    ///
    /// Провайдеры без нативного SSE-стриминга автоматически получают эту реализацию.
    /// Ответ возвращается единым блоком: сначала `.thinking` (если есть reasoning), затем `.content`, затем `.usage`.
    func streamComplete(
        messages: [LLMMessage],
        tools: [ToolDefinition]?,
        temperature: Double,
        maxTokens: Int?,
        stop: [String]?
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await complete(
                        messages: messages, tools: tools,
                        temperature: temperature, maxTokens: maxTokens, stop: stop
                    )
                    if let reasoning = response.message.reasoning, !reasoning.isEmpty {
                        continuation.yield(.thinking(reasoning))
                    }
                    continuation.yield(.content(response.message.content))
                    if let usage = response.usage {
                        continuation.yield(.usage(usage))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
