//
//  NotesPersistenceService.swift
//  AI Advent Challenge
//

import Foundation

final class NotesPersistenceService {
    private let notesDirectory: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        notesDirectory = appSupport.appendingPathComponent("AgentState/notes")
        try? FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
    }

    func saveNote(title: String, content: String) throws {
        let safeTitle = title
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        let url = notesDirectory.appendingPathComponent("\(safeTitle).txt")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func listNotes() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: notesDirectory.path)) ?? []
        return files.filter { $0.hasSuffix(".txt") }.map { String($0.dropLast(4)) }
    }
}
