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
    private let temperatureStore: TemperatureStore
    private let modelStore: ModelStore

    init(
        providerFactory: ProviderFactory,
        toolExecutor: ToolExecutor,
        temperatureStore: TemperatureStore,
        modelStore: ModelStore
    ) {
        self.providerFactory = providerFactory
        self.toolExecutor = toolExecutor
        self.temperatureStore = temperatureStore
        self.modelStore = modelStore
    }

    func execute(agentType: AgentType) throws -> Agent {
        let provider = try providerFactory.createProvider(modelStore.selectedProvider)
        return DefaultAgent(
            agentType: agentType,
            provider: provider,
            toolExecutor: toolExecutor,
            temperatureStore: temperatureStore
        )
    }
}
