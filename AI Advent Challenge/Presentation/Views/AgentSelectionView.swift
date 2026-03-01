//
//  AgentSelectionView.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import SwiftUI

struct AgentSelectionView: View {
    @StateObject var viewModel: AgentSelectionViewModel
    let onAgentSelected: (AgentTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.templates) { template in
                    Button {
                        onAgentSelected(template)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: template.icon)
                                .font(.system(size: 32))
                                .foregroundStyle(.blue)
                                .frame(width: 50)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name)
                                    .font(.headline)

                                Text(template.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)

                                if let policyDesc = template.compressionPolicyDescription {
                                    Text(policyDesc)
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Новый диалог")
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
