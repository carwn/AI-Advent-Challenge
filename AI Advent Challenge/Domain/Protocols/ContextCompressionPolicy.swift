//
//  ContextCompressionPolicy.swift
//  AI Advent Challenge
//

import Foundation

/// Стратегия сжатия контекста разговора перед отправкой в LLM.
protocol ContextCompressionPolicy: AnyObject {

    /// Принимает полный Conversation, возвращает:
    /// - `apiConversation`: сжатый контекст для передачи в LLM
    /// - `summaryUsage`: токены, потраченные на генерацию summary (если была); агент добавляет их сам
    func compress(_ conversation: Conversation) async -> (apiConversation: Conversation, summaryUsage: UsageInfo?)

    /// Сбрасывает внутреннее состояние. Вызывается при очистке разговора.
    func reset()
}
