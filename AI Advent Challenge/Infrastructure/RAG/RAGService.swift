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
}
