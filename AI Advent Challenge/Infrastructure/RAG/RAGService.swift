// RAGService.swift
// Фасад: один объект для всего RAG-поиска в приложении.
// Используй именно его в ViewModel / SwiftUI.

import Foundation
import Combine

@MainActor
class RAGService: ObservableObject {
    @Published var isReady = false
    @Published var isSearching = false
    @Published var error: String?

    private let index = VectorIndex()
    private let embedding: EmbeddingProvider

    // MARK: — Инициализация

    /// Voyage API (требует сеть)
    init(voyageApiKey: String) {
        self.embedding = VoyageEmbeddingService(apiKey: voyageApiKey)
    }

    /// CoreML (оффлайн)
    init(coreMLModelURL: URL) throws {
        self.embedding = try CoreMLEmbeddingService(modelURL: coreMLModelURL)
    }

    // MARK: — Загрузка индекса

    func loadIndex() {
        do {
            // Сначала пробуем Documents (обновляемая версия),
            // затем Bundle (встроенная при сборке)
            if let _ = try? index.loadFromDocuments() {
                print("📦 Индекс из Documents")
            } else {
                try index.loadFromBundle()
                print("📦 Индекс из Bundle")
            }
            isReady = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: — Поиск

    func search(
        query: String,
        topK: Int = 5,
        strategy: String? = nil
    ) async -> [SearchResult] {
        guard isReady else {
            error = "Индекс не загружен"
            return []
        }
        isSearching = true
        defer { isSearching = false }

        do {
            let results = try await index.search(
                query: query,
                embeddingProvider: embedding,
                topK: topK,
                strategy: strategy,
                minScore: 0.25          // отсекаем совсем нерелевантное
            )
            return results
        } catch {
            self.error = error.localizedDescription
            return []
        }
    }

    /// Контекст для промпта к LLM (топ чанки → строка)
    func buildContext(for query: String, topK: Int = 3) async -> String {
        let results = await search(query: query, topK: topK)
        guard !results.isEmpty else { return "" }

        return results.map { r in
            "[\(r.chunk.source) / \(r.chunk.section)]\n\(r.chunk.text)"
        }.joined(separator: "\n\n---\n\n")
    }

    /// Расширенный поиск с поддержкой RAGMode и статистикой
    func buildContextWithDetails(
        for query: String,
        mode: RAGMode,
        finalK: Int = 3,
        rewriteQueryProvider: ((String) async -> String?)? = nil
    ) async -> (context: String, stats: RAGSearchStats)? {
        guard mode != .off, isReady else { return nil }

        // 1. Query rewrite (для .rewrite, .full)
        var searchQuery = query
        var rewrittenQuery: String? = nil
        if (mode == .rewrite || mode == .full), let provider = rewriteQueryProvider {
            if let rewritten = await provider(query), !rewritten.isEmpty {
                rewrittenQuery = rewritten
                searchQuery = rewritten
            }
        }

        // 2. Embed query (один раз)
        let prefixed = "Represent this sentence for searching: \(searchQuery)"
        guard let queryEmbedding = try? await embedding.embed(prefixed) else { return nil }

        // 3. Поиск кандидатов
        let initialK = (mode == .rerank || mode == .full) ? 10 : finalK
        let minScore: Float = (mode == .rerank || mode == .full) ? 0.2 : 0.25
        let candidates = index.search(queryEmbedding: queryEmbedding, topK: initialK,
                                      strategy: nil, minScore: minScore)

        // 4. MMR (для .rerank, .full)
        let results: [SearchResult]
        if mode == .rerank || mode == .full {
            results = index.mmrSearch(candidates: candidates, queryEmbedding: queryEmbedding,
                                      finalK: finalK, lambda: 0.7, minFinalScore: 0.35)
        } else {
            results = candidates
        }

        guard !results.isEmpty else { return nil }

        let chunkTexts = results.enumerated().map { i, r in
            "[\(i+1)] \(r.chunk.source) / \(r.chunk.section)\n\(r.chunk.text)"
        }
        let context = results.enumerated().map { i, r in
            "[\(i+1)] \(r.chunk.source)\n\(r.chunk.text)"
        }.joined(separator: "\n\n---\n\n")

        let stats = RAGSearchStats(
            mode: mode,
            rewrittenQuery: rewrittenQuery,
            candidateCount: candidates.count,
            finalCount: results.count,
            topScores: results.map { $0.score },
            chunkTexts: chunkTexts,
            sources: results.map { $0.chunk.source },
            sections: results.map { $0.chunk.section },
            chunkIds: results.map { $0.chunk.chunkId }
        )

        return (context, stats)
    }
}
