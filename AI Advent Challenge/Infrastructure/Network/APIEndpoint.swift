//
//  APIEndpoint.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

enum APIEndpoint {
    case openAIChatCompletion

    var url: URL {
        switch self {
        case .openAIChatCompletion:
            return URL(string: "https://api.proxyapi.ru/openai/v1/chat/completions")!
        }
    }
}
