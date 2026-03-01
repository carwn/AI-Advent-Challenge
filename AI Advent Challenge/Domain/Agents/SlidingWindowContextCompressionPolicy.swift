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

    func compress(_ conversation: Conversation) async -> (apiConversation: Conversation, summaryUsage: UsageInfo?, details: String?) {
        var msgs: [Message] = []

        if let sys = conversation.messages.first, sys.role == .system {
            msgs.append(sys)
        }

        let nonSystem = conversation.messages.filter { $0.role != .system && $0.role != .summaryUsage }
        let kept = min(windowSize, nonSystem.count)
        let dropped = nonSystem.count - kept
        msgs.append(contentsOf: nonSystem.suffix(kept))

        var apiConv = Conversation(systemPrompt: "")
        apiConv.messages = msgs

        let details: String? = dropped > 0 ? "история: последние \(kept) сообщений, отброшено \(dropped)" : nil
        return (apiConv, nil, details)
    }

    func reset() {
        // Нет внутреннего состояния — ничего не сбрасываем
    }
}
