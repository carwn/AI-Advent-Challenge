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
    @Published var availableAgents: [AgentType] = AgentType.allCases
    @Published var selectedAgent: AgentType?

    private let createAgentUseCase: CreateAgentUseCase
    private let conversationRepository: ConversationRepository

    init(
        createAgentUseCase: CreateAgentUseCase,
        conversationRepository: ConversationRepository
    ) {
        self.createAgentUseCase = createAgentUseCase
        self.conversationRepository = conversationRepository
    }

    func selectAgent(_ agentType: AgentType) {
        selectedAgent = agentType
    }

    func createConversation(with agentType: AgentType) -> Conversation {
        conversationRepository.getOrCreateConversation(agentType: agentType)
    }
}
