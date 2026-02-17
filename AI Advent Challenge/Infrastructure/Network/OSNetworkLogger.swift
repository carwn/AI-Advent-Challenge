//
//  OSNetworkLogger.swift
//  AI Advent Challenge
//
//  Created by Claude on 17.02.2026.
//

import Foundation
import os

final class OSNetworkLogger: NetworkLogger {
    private let logger = Logger(subsystem: "com.aiapp", category: "Network")

    func logRequest(method: String, url: URL, headers: [String: String], body: Data?) {
        let sanitizedHeaders = sanitize(headers: headers)
        let bodyString = body.map { formatBody($0) } ?? "<no body>"
        logger.debug("--> \(method, privacy: .public) \(url.absoluteString, privacy: .public)\nHeaders: \(sanitizedHeaders, privacy: .public)\nBody: \(bodyString, privacy: .public)")
    }

    func logResponse(statusCode: Int, url: URL, headers: [String: String], body: Data) {
        logger.debug("<-- \(statusCode, privacy: .public) \(url.absoluteString, privacy: .public)\nHeaders: \(headers, privacy: .public)\nBody: \(self.formatBody(body), privacy: .public)")
    }

    func logError(url: URL, error: Error) {
        logger.error("<-- ERROR \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }

    private func formatBody(_ data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
           let string = String(data: pretty, encoding: .utf8) {
            return string
        }
        return String(data: data, encoding: .utf8) ?? "<non-UTF8, \(data.count) bytes>"
    }

    private func sanitize(headers: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: headers.map { key, value in
            guard key.lowercased() == "authorization" else { return (key, value) }
            let suffix = value.count > 4 ? String(value.suffix(4)) : "****"
            return (key, "...\(suffix)")
        })
    }
}
