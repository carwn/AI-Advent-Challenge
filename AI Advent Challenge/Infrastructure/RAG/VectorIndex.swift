// VectorIndex.swift (обновлённая версия)
// Загружает chunks.json, ищет через cosine similarity.
// Эмбеддинг запроса — через EmbeddingProvider (API или CoreML).

import Foundation
import Accelerate

// MARK: — Модели данных

struct Chunk: Codable {
    let chunkId: String
    let text: String
    let source: String
    let title: String
    let section: String
    let strategy: String
    let chunkIndex: Int
    let tokenEstimate: Int
    var embedding: [Float]?

    enum CodingKeys: String, CodingKey {
        case chunkId = "chunk_id"
        case text, source, title, section, strategy
        case chunkIndex = "chunk_index"
        case tokenEstimate = "token_estimate"
        case embedding
    }
}

struct SearchResult {
    let chunk: Chunk
    let score: Float    // cosine similarity: 0..1, чем выше — тем релевантнее
    let rank: Int
}

// MARK: — Индекс

class VectorIndex {
    private var chunks: [Chunk] = []
    private var matrix: [[Float]] = []      // [n × dim]

    // MARK: Загрузка

    /// Загружает chunks.json из Bundle (добавь файл в Xcode → Target)
    func loadFromBundle(filename: String = "chunks") throws {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            throw IndexError.fileNotFound("\(filename).json не найден в Bundle")
        }
        try load(from: url)
    }

    /// Загружает chunks.json из Documents (например, после скачивания обновления)
    func loadFromDocuments(filename: String = "chunks") throws {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("\(filename).json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw IndexError.fileNotFound("Documents/\(filename).json не найден")
        }
        try load(from: url)
    }

    private func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        var all = try JSONDecoder().decode([Chunk].self, from: data)

        // Берём только чанки с эмбеддингами
        all = all.filter { $0.embedding != nil }
        chunks = all
        matrix = all.compactMap { $0.embedding }

        print("✅ VectorIndex загружен: \(chunks.count) чанков, dim=\(matrix.first?.count ?? 0)")
    }

    var isLoaded: Bool { !chunks.isEmpty }

    // MARK: Поиск

    /// Основной метод: текст запроса → top-K результатов
    func search(
        query: String,
        embeddingProvider: EmbeddingProvider,
        topK: Int = 5,
        strategy: String? = nil,          // "fixed" | "structural" | nil (все)
        minScore: Float = 0.0             // отсекаем нерелевантные
    ) async throws -> [SearchResult] {
        guard isLoaded else { throw IndexError.notLoaded }

        // bge требует префикс для запросов (документы при индексации — без префикса)
        let prefixedQuery = "Represent this sentence for searching: \(query)"
        let queryVec = try await embeddingProvider.embed(prefixedQuery)

        // 2. Cosine similarity со всеми чанками
        return search(queryEmbedding: queryVec, topK: topK,
                      strategy: strategy, minScore: minScore)
    }

    /// Поиск по готовому вектору (если эмбеддинг уже есть)
    func search(
        queryEmbedding: [Float],
        topK: Int = 5,
        strategy: String? = nil,
        minScore: Float = 0.0
    ) -> [SearchResult] {
        guard isLoaded else { return [] }

        let dim = queryEmbedding.count
        var qNorm = l2Normalize(queryEmbedding)

        var scored: [(index: Int, score: Float)] = []

        for (i, emb) in matrix.enumerated() {
            // Фильтр по стратегии
            if let s = strategy, chunks[i].strategy != s { continue }

            // Dot product (≡ cosine, т.к. оба вектора нормализованы)
            var score: Float = 0
            var e = emb
            vDSP_dotpr(&qNorm, 1, &e, 1, &score, vDSP_Length(min(dim, e.count)))

            if score >= minScore {
                scored.append((i, score))
            }
        }

        // Сортировка и top-K
        let topResults = scored
            .sorted { $0.score > $1.score }
            .prefix(topK)

        return topResults.enumerated().map { rank, item in
            SearchResult(chunk: chunks[item.index], score: item.score, rank: rank + 1)
        }
    }

    // MARK: Утилиты

    private func l2Normalize(_ v: [Float]) -> [Float] {
        var out = v
        var len: Float = 0
        vDSP_svesq(v, 1, &len, vDSP_Length(v.count))
        len = sqrt(len)
        guard len > 1e-8 else { return out }
        vDSP_vsdiv(out, 1, &len, &out, 1, vDSP_Length(out.count))
        return out
    }

    enum IndexError: Error, LocalizedError {
        case fileNotFound(String)
        case notLoaded

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let f): return "Файл не найден: \(f)"
            case .notLoaded:           return "Индекс не загружен"
            }
        }
    }
}
