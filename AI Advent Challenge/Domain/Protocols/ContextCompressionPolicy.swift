//
//  ContextCompressionPolicy.swift
//  AI Advent Challenge
//

import Foundation

/// Стратегия сжатия контекста разговора перед отправкой в LLM.
protocol ContextCompressionPolicy: AnyObject {

    /// Краткое описание политики сжатия для отображения в UI.
    var description: String { get }

    /// Принимает полный Conversation, возвращает:
    /// - `apiConversation`: сжатый контекст для передачи в LLM
    /// - `summaryUsage`: токены, потраченные на генерацию summary (если была); агент добавляет их сам
    /// - `details`: текст для отображения в чате (размер окна + факты/summary); nil — если сжатия не было
    func compress(_ conversation: Conversation) async -> (apiConversation: Conversation, summaryUsage: UsageInfo?, details: String?)

    /// Сбрасывает внутреннее состояние. Вызывается при очистке разговора.
    func reset()
}
