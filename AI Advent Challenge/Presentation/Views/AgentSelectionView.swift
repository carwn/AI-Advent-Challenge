//
//  AgentSelectionView.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import SwiftUI

struct AgentSelectionView: View {
    @StateObject var viewModel: AgentSelectionViewModel
    let onAgentSelected: (AgentType) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(viewModel.availableAgents) { agent in
                Button {
                    onAgentSelected(agent)
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: agent.icon)
                            .font(.system(size: 32))
                            .foregroundStyle(.blue)
                            .frame(width: 50)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(agent.rawValue)
                                .font(.headline)

                            Text(agent.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Выбор агента")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
        }
    }
}
