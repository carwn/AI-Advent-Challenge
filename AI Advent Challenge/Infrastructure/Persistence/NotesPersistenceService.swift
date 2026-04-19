//
//  NotesPersistenceService.swift
//  AI Advent Challenge
//

import Foundation

final class NotesPersistenceService {
    private let notesURL: URL

    init() {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        notesURL = appSupport
            .appendingPathComponent("AgentState", isDirectory: true)
            .appendingPathComponent("notes", isDirectory: true)
        try? FileManager.default.createDirectory(at: notesURL, withIntermediateDirectories: true)
    }

    func saveNote(title: String, content: String) throws {
        let safeTitle = title
            .components(separatedBy: .init(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
        guard !safeTitle.isEmpty else {
            throw NotesPersistenceError.invalidTitle(title)
        }
        let url = notesURL.appendingPathComponent("\(safeTitle).txt")
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}

enum NotesPersistenceError: LocalizedError {
    case invalidTitle(String)

    var errorDescription: String? {
        switch self {
        case .invalidTitle(let t):
            return "Invalid note title: '\(t)'"
        }
    }
}
