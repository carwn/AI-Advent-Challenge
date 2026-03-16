// BertTokenizer.swift
// Минимальный BERT-токенайзер для CoreML-пути.
// Нужен только если используешь CoreML (оффлайн).
// Для API-пути (Voyage) этот файл не нужен.

import Foundation
import CoreML

struct TokenizerOutput {
    let inputIds: [Int32]
    let attentionMask: [Int32]
    let tokenTypeIds: [Int32]
}

class BertTokenizer {
    private var vocab: [String: Int] = [:]
    private let clsToken = "[CLS]"
    private let sepToken = "[SEP]"
    private let unkToken = "[UNK]"
    private let padToken = "[PAD]"

    // vocab.txt должен лежать в Bundle — vocab от BAAI/bge-small-en-v1.5
    // https://huggingface.co/BAAI/bge-small-en-v1.5/blob/main/vocab.txt
    init(vocabFile: String = "vocab") {
        guard let url = Bundle.main.url(forResource: vocabFile, withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            print("⚠️ vocab.txt не найден — используем заглушку")
            return
        }
        for (i, line) in content.components(separatedBy: "\n").enumerated() {
            vocab[line.trimmingCharacters(in: .whitespaces)] = i
        }
    }

    func tokenize(_ text: String, maxLength: Int = 128) -> TokenizerOutput {
        // Простая WordPiece-токенизация (достаточно для базового использования)
        var tokens = [clsToken]
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        for word in words {
            if vocab[word] != nil {
                tokens.append(word)
            } else {
                // Разбиваем на символы как [UNK]-фолбэк
                tokens.append(contentsOf: wordPiece(word))
            }
            if tokens.count >= maxLength - 1 { break }
        }
        tokens.append(sepToken)

        // Паддинг до maxLength
        let ids   = tokens.map { Int32(vocab[$0] ?? vocab[unkToken] ?? 0) }
        let padId  = Int32(vocab[padToken] ?? 0)
        let padded = ids + Array(repeating: padId, count: max(0, maxLength - ids.count))
        let mask   = ids.map { _ in Int32(1) } + Array(repeating: Int32(0), count: max(0, maxLength - ids.count))
        let types  = Array(repeating: Int32(0), count: maxLength)

        return TokenizerOutput(
            inputIds:      Array(padded.prefix(maxLength)),
            attentionMask: Array(mask.prefix(maxLength)),
            tokenTypeIds:  types
        )
    }

    // Упрощённый WordPiece
    private func wordPiece(_ word: String) -> [String] {
        var pieces: [String] = []
        var start = word.startIndex
        while start < word.endIndex {
            var end = word.endIndex
            var found = false
            let prefix = start == word.startIndex ? "" : "##"
            while end > start {
                let sub = prefix + word[start..<end]
                if vocab[sub] != nil {
                    pieces.append(sub)
                    start = end
                    found = true
                    break
                }
                end = word.index(before: end)
            }
            if !found {
                pieces.append(unkToken)
                break
            }
        }
        return pieces.isEmpty ? [unkToken] : pieces
    }
}

// MARK: — Хелпер: [Int32] → MLMultiArray

extension MLMultiArray {
    convenience init(_ values: [Int32]) throws {
        try self.init(shape: [1, NSNumber(value: values.count)], dataType: .int32)
        for (i, v) in values.enumerated() { self[i] = NSNumber(value: v) }
    }
}
