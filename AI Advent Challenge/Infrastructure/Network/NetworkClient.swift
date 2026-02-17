//
//  NetworkClient.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

final class NetworkClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger: NetworkLogger?

    init(session: URLSession = .shared, logger: NetworkLogger? = nil) {
        self.session = session
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        self.logger = logger
    }

    func request<T: Decodable, B: Encodable>(
        endpoint: APIEndpoint,
        method: HTTPMethod,
        body: B?,
        headers: [String: String]
    ) async throws -> T {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = method.rawValue

        // Add headers
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        // Add body
        if let body = body {
            request.httpBody = try encoder.encode(body)
        }

        logger?.logRequest(method: method.rawValue, url: endpoint.url, headers: headers, body: request.httpBody)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            logger?.logError(url: endpoint.url, error: error)
            throw error
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            let error = NetworkError.invalidResponse
            logger?.logError(url: endpoint.url, error: error)
            throw error
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let error = NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
            logger?.logError(url: endpoint.url, error: error)
            throw error
        }

        let responseHeaders = httpResponse.allHeaderFields.reduce(into: [String: String]()) { acc, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                acc[key] = value
            }
        }
        logger?.logResponse(statusCode: httpResponse.statusCode, url: endpoint.url, headers: responseHeaders, body: data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw NetworkError.decodingError(error)
        }
    }
}
