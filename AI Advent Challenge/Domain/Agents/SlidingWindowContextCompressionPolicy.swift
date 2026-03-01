//
//  SlidingWindowContextCompressionPolicy.swift
//  AI Advent Challenge
//

import Foundation

/// Реализация ContextCompressionPolicy на основе скользящего окна.
/// В API передаются только последние `windowSize` сообщений (не считая system).
final class SlidingWindowContextCompressionPolicy: ContextCompressionPolicy {

    private let windowSize: Int

    /// - Parameter windowSize: количество последних сообщений, передаваемых в API (по умолчанию 5)
    init(windowSize: Int = 5) {
        self.windowSize = windowSize
    }

    // MARK: - ContextCompressionPolicy

    var description: String { "Sliding Window: последние \(windowSize) сообщений" }

    func compress(_ conversation: Conversation) async -> (apiConversation: Conversation, summaryUsage: UsageInfo?) {
        var msgs: [Message] = []

        if let sys = conversation.messages.first, sys.role == .system {
            msgs.append(sys)
        }

        let nonSystem = conversation.messages.filter { $0.role != .system && $0.role != .summaryUsage }
        msgs.append(contentsOf: nonSystem.suffix(windowSize))

        var apiConv = Conversation(systemPrompt: "")
        apiConv.messages = msgs
        return (apiConv, nil)
    }

    func reset() {
        // Нет внутреннего состояния — ничего не сбрасываем
    }
}
