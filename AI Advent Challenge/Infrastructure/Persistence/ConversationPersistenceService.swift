//
//  ConversationPersistenceService.swift
//  AI Advent Challenge
//
//  Created by Claude on 24.02.2026.
//

import Foundation

final class ConversationPersistenceService {
    private let baseURL: URL
    private let indexURL: URL

    init() {
        let appSupport = FileManager.default.appSupportDirectory
        baseURL = appSupport.appendingPathComponent("AgentState", isDirectory: true)
        indexURL = baseURL.appendingPathComponent("conversations_index.json")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    // MARK: - Conversation data

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

    func copyConversation(from sourceKey: String, to destinationKey: String) {
        let src = fileURL(for: sourceKey)
        let dst = fileURL(for: destinationKey)
        guard FileManager.default.fileExists(atPath: src.path) else { return }
        try? FileManager.default.copyItem(at: src, to: dst)
    }

    func copyPolicyCaches(from sourceKey: String, to destinationKey: String) {
        for suffix in ["_summary", "_facts", "_working"] {
            let src = baseURL.appendingPathComponent("\(sourceKey)\(suffix).json")
            let dst = baseURL.appendingPathComponent("\(destinationKey)\(suffix).json")
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            try? FileManager.default.copyItem(at: src, to: dst)
        }
    }

    func deleteAllData() {
        try? FileManager.default.removeItem(at: baseURL)
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        baseURL.appendingPathComponent("\(key).json")
    }

    // MARK: - Conversation records (index)

    func loadRecords() -> [ConversationRecord] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: indexURL)
            return try JSONDecoder().decode([ConversationRecord].self, from: data)
        } catch {
            print("[ConversationPersistenceService] loadRecords failed: \(error)")
            return []
        }
    }

    func saveRecord(_ record: ConversationRecord) {
        var records = loadRecords()
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            records[idx] = record
        } else {
            records.append(record)
        }
        saveRecords(records)
    }

    func deleteRecord(id: UUID) {
        var records = loadRecords()
        records.removeAll { $0.id == id }
        saveRecords(records)
    }

    func updateRecord(id: UUID, firstUserMessage: String?, lastPreview: String?, lastDate: Date?) {
        var records = loadRecords()
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        if let msg = firstUserMessage {
            records[idx].title = String(msg.prefix(40))
        }
        records[idx].lastMessagePreview = lastPreview
        records[idx].lastMessageDate = lastDate
        saveRecords(records)
    }

    private func saveRecords(_ records: [ConversationRecord]) {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            print("[ConversationPersistenceService] saveRecords failed: \(error)")
        }
    }
}
