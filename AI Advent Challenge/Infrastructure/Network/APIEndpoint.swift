//
//  APIEndpoint.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

enum APIEndpoint {
    case openAIChatCompletion
    case geminiGenerateContent(model: String)
    case anthropicMessages
    case ollamaChatCompletion

    var url: URL {
        switch self {
        case .openAIChatCompletion:
            return URL(string: "https://api.proxyapi.ru/openai/v1/chat/completions")!
        case .geminiGenerateContent(let model):
            return URL(string: "https://api.proxyapi.ru/google/v1beta/models/\(model):generateContent")!
        case .anthropicMessages:
            return URL(string: "https://api.proxyapi.ru/anthropic/v1/messages")!
        case .ollamaChatCompletion:
            return URL(string: "http://localhost:11434/v1/chat/completions")!
        }
    }
}
