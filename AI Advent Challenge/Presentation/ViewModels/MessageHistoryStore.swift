//
//  MessageHistoryStore.swift
//  AI Advent Challenge
//
//  Created by Claude on 18.02.2026.
//

import Foundation
import Combine

@MainActor
final class MessageHistoryStore: ObservableObject {
    @Published private(set) var items: [String] = []

    private let userDefaultsKey = "messageHistory"

    init() {
        items = UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? []
    }

    func add(_ text: String) {
        items.removeAll { $0 == text }
        items.insert(text, at: 0)
        if items.count > 10 {
            items = Array(items.prefix(10))
        }
        persist()
    }

    func remove(_ text: String) {
        items.removeAll { $0 == text }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(items, forKey: userDefaultsKey)
    }
}
