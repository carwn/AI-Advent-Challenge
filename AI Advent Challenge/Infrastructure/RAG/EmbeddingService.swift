// EmbeddingService.swift
// Получение эмбеддингов на iOS: два варианта
//   A) Voyage API (Anthropic) — просто, требует сеть
//   B) CoreML — оффлайн, требует конвертацию модели на Mac

import Foundation

// MARK: — Протокол (оба варианта взаимозаменяемы)

protocol EmbeddingProvider {
    func embed(_ text: String) async throws -> [Float]
}

// MARK: — A) Voyage API (рекомендуется для старта)

class VoyageEmbeddingService: EmbeddingProvider {
    private let apiKey: String
    private let model: String
    private let endpoint = URL(string: "https://api.voyageai.com/v1/embeddings")!

    init(apiKey: String, model: String = "voyage-3-lite") {
        self.apiKey = apiKey
        self.model = model
    }

    func embed(_ text: String) async throws -> [Float] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "input": [text]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown error"
            throw EmbeddingError.apiError(msg)
        }

        let decoded = try JSONDecoder().decode(VoyageResponse.self, from: data)
        guard let embedding = decoded.data.first?.embedding else {
            throw EmbeddingError.emptyResponse
        }
        return embedding
    }

    // Пакетная генерация (для переиндексации прямо на устройстве)
    func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["model": model, "input": texts]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(VoyageResponse.self, from: data)
        return decoded.data
            .sorted { $0.index < $1.index }
            .map { $0.embedding }
    }

    private struct VoyageResponse: Decodable {
        struct Item: Decodable {
            let index: Int
            let embedding: [Float]
        }
        let data: [Item]
    }
}

// MARK: — B) CoreML (оффлайн)

import CoreML

class CoreMLEmbeddingService: EmbeddingProvider {
    private let model: MLModel
    private let tokenizer: BertTokenizer

    // modelURL — путь к .mlpackage в bundle или Documents
    init(modelURL: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine  // используем Neural Engine
        self.model = try MLModel(contentsOf: modelURL, configuration: config)
        self.tokenizer = BertTokenizer()
    }

    func embed(_ text: String) async throws -> [Float] {
        let tokens = tokenizer.tokenize(text, maxLength: 128)

        let inputIds  = try MLMultiArray(tokens.inputIds)
        let attMask   = try MLMultiArray(tokens.attentionMask)
        let tokenType = try MLMultiArray(tokens.tokenTypeIds)

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids":      MLFeatureValue(multiArray: inputIds),
            "attention_mask": MLFeatureValue(multiArray: attMask),
            "token_type_ids": MLFeatureValue(multiArray: tokenType),
        ])

        let output = try await model.prediction(from: input)

        guard let rawEmb = output.featureValue(for: "embeddings")?.multiArrayValue else {
            throw EmbeddingError.coreMLOutputMissing
        }

        // Извлекаем Float-массив и нормализуем
        var vec = (0..<rawEmb.count).map { Float(truncating: rawEmb[$0]) }
        return l2Normalize(vec)
    }

    private func l2Normalize(_ v: [Float]) -> [Float] {
        let len = sqrt(v.map { $0 * $0 }.reduce(0, +))
        guard len > 0 else { return v }
        return v.map { $0 / len }
    }
}

// MARK: — Ошибки

enum EmbeddingError: Error, LocalizedError {
    case apiError(String)
    case emptyResponse
    case coreMLOutputMissing
    case tokenizerError

    var errorDescription: String? {
        switch self {
        case .apiError(let msg):        return "API Error: \(msg)"
        case .emptyResponse:            return "Empty embedding response"
        case .coreMLOutputMissing:      return "CoreML: output 'embeddings' not found"
        case .tokenizerError:           return "Tokenizer failed"
        }
    }
}
