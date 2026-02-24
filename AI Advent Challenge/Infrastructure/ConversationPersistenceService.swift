//
//  ConversationPersistenceService.swift
//  AI Advent Challenge
//
//  Created by Claude on 24.02.2026.
//

import Foundation

final class ConversationPersistenceService {
    private let baseURL: URL

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseURL = appSupport.appendingPathComponent("AgentState", isDirectory: true)
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    func save(_ conversation: Conversation, forKey key: String) {
        let url = fileURL(for: key)
        do {
            let data = try JSONEncoder().encode(conversation)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[ConversationPersistenceService] Save failed '\(key)': \(error)")
        }
    }

    func load(forKey key: String) -> Conversation? {
        let url = fileURL(for: key)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Conversation.self, from: data)
        } catch {
            print("[ConversationPersistenceService] Load failed '\(key)': \(error)")
            return nil
        }
    }

    func delete(forKey key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    private func fileURL(for key: String) -> URL {
        baseURL.appendingPathComponent("\(key).json")
    }
}
