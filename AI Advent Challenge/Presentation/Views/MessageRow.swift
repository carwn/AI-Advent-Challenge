//
//  MessageRow.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import SwiftUI

struct MessageRow: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(backgroundColor)
                    .foregroundColor(foregroundColor)
                    .cornerRadius(16)

                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tool Calls:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(toolCalls) { toolCall in
                            Text("→ \(toolCall.function.name)")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(8)
                    .background(Color(uiColor: .systemGray6))
                    .cornerRadius(8)
                }

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if message.role == .assistant {
                Spacer()
            }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return .blue
        case .assistant:
            return Color(uiColor: .systemGray5)
        case .tool:
            return Color(uiColor: .systemGray6)
        case .system:
            return .clear
        }
    }

    private var foregroundColor: Color {
        message.role == .user ? .white : .primary
    }
}
