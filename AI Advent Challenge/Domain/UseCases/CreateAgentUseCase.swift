//
//  CreateAgentUseCase.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

final class CreateAgentUseCase {
    private let providerFactory: ProviderFactory
    private let toolExecutor: ToolExecutor

    init(providerFactory: ProviderFactory, toolExecutor: ToolExecutor) {
        self.providerFactory = providerFactory
        self.toolExecutor = toolExecutor
    }

    func execute(agentType: AgentType) throws -> Agent {
        let provider = try providerFactory.createProvider(.openAI)
        return DefaultAgent(
            agentType: agentType,
            provider: provider,
            toolExecutor: toolExecutor
        )
    }
}
