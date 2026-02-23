//
//  MultiExpertAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class MultiExpertAgent: Agent {
    let name = "Совет экспертов"
    let icon = "person.3"
    let description = "Привлекает трёх экспертов, получает их мнения и синтезирует вывод"
    var conversation: Conversation

    private let provider: LLMProvider
    private let toolExecutor: ToolExecutor
    private let systemPrompt = """
        You are a multi-expert reasoning system. For every user request:

        1. **Identify Experts**: Determine 3 distinct expert roles most relevant to the task. Name each role clearly.

        2. **Expert Opinions**: For each expert, present their analysis in this format:
           ### [Expert Role]
           [Their perspective, reasoning, and recommendation]

        3. **Synthesis**: After all three opinions, add a section:
           ### Итоговый вывод
           Synthesize the key insights from all three experts into a final, balanced conclusion.

        Always complete all three expert opinions before synthesizing.
        Keep each expert's opinion concise — 3–5 sentences maximum per expert.
        """
    private let availableTools: [ToolDefinition] = []
    private let maxTokens = 2000
    private let stopWords: [String]? = nil
    private let temperature: Double = 0.5

    init(provider: LLMProvider, toolExecutor: ToolExecutor) {
        self.provider = provider
        self.toolExecutor = toolExecutor
        self.conversation = Conversation(systemPrompt: systemPrompt)
    }

    func send(_ text: String) async throws -> AgentResponse {
        let (response, updated) = try await AgentSending.send(
            userText: text,
            conversation: conversation,
            provider: provider,
            tools: availableTools,
            temperature: temperature,
            maxTokens: maxTokens,
            stopWords: stopWords,
            toolExecutor: toolExecutor
        )
        conversation = updated
        return response
    }

    func clearConversation() {
        conversation = Conversation(systemPrompt: systemPrompt)
    }
}
