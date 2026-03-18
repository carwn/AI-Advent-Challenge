// RAGMode.swift
// Режимы поиска в базе знаний RAGAgent.

import Foundation

enum RAGMode: String, Codable, CaseIterable {
    case off, basic, rerank, rewrite, full

    var displayName: String {
        switch self {
        case .off:     return "off"
        case .basic:   return "basic"
        case .rerank:  return "rerank"
        case .rewrite: return "rewrite"
        case .full:    return "full"
        }
    }

    var next: RAGMode {
        switch self {
        case .off:     return .basic
        case .basic:   return .rerank
        case .rerank:  return .rewrite
        case .rewrite: return .full
        case .full:    return .off
        }
    }
}

struct RAGSearchStats {
    let mode: RAGMode
    let rewrittenQuery: String?   // nil если rewrite не применялся
    let candidateCount: Int       // до MMR / фильтрации
    let finalCount: Int           // после
    let topScores: [Float]        // оценки чанков, попавших в контекст
    let chunkTexts: [String]      // отдельные чанки для UI (без парсинга строки)

    var summaryLine: String {
        var parts = ["📚 Режим: \(mode.displayName)"]
        if let q = rewrittenQuery { parts.append("Запрос: \"\(q)\"") }
        parts.append("Кандидаты: \(candidateCount) → \(finalCount)")
        let scores = topScores.prefix(5).map { String(format: "%.2f", $0) }.joined(separator: ", ")
        if !scores.isEmpty { parts.append("Оценки: \(scores)") }
        return parts.joined(separator: " | ")
    }
}
