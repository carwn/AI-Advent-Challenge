//
//  ToolExecutor.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

protocol ToolExecutor {
    func execute(_ toolCall: ToolCall) async throws -> String
    func canExecute(toolName: String) -> Bool
}
