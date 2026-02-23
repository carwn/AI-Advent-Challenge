//
//  Agent.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

protocol Agent: AnyObject {
    var name: String { get }
    var icon: String { get }
    var description: String { get }
    var conversation: Conversation { get set }
    func send(_ text: String) async throws
    func clearConversation()
}
