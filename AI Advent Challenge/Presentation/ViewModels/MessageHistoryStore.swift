//
//  MessageHistoryStore.swift
//  AI Advent Challenge
//
//  Created by Claude on 18.02.2026.
//

import Combine

@MainActor
final class MessageHistoryStore: ObservableObject {
    @Published private(set) var items: [String] = []

    func add(_ text: String) {
        guard !items.contains(text) else { return }
        items.append(text)
    }
}
