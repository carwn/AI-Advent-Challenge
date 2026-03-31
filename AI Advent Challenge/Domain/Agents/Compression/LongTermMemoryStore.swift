//
//  LongTermMemoryStore.swift
//  AI Advent Challenge
//

import Foundation
import Combine

/// Хранилище долговременной памяти агента.
///
/// Текст редактируется пользователем через Settings и разделяется
/// между всеми разговорами одного агента.
final class LongTermMemoryStore: ObservableObject {
    @Published var text: String = ""
    private let fileURL: URL

    init(agentKey: String) {
        let appSupport = FileManager.default.appSupportDirectory
        let dir = appSupport.appendingPathComponent("AgentState", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("long_term_memory_\(agentKey).txt")
        if let saved = try? String(contentsOf: fileURL, encoding: .utf8) {
            text = saved
        }
    }

    func save() {
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Синхронный читатель для политики сжатия
    func currentText() -> String { text }
}
