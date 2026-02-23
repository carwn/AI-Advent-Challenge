//
//  AgentSelectionViewModel.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation
import Combine

@MainActor
final class AgentSelectionViewModel: ObservableObject {
    @Published var availableAgents: [any Agent]

    init(agents: [any Agent]) {
        self.availableAgents = agents
    }
}
