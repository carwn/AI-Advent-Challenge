//
//  NetworkLogger.swift
//  AI Advent Challenge
//
//  Created by Claude on 17.02.2026.
//

import Foundation

protocol NetworkLogger {
    func logRequest(method: String, url: URL, headers: [String: String], body: Data?)
    func logResponse(statusCode: Int, url: URL, headers: [String: String], body: Data)
    func logError(url: URL, error: Error)
}
