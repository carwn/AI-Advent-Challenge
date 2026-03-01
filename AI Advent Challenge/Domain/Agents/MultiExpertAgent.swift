//
//  MultiExpertAgent.swift
//  AI Advent Challenge
//
//  Created by Claude on 23.02.2026.
//

import Foundation

final class MultiExpertAgent: BaseAgent {
    override var name: String { "Совет экспертов" }
    override var icon: String { "person.3" }
    override var description: String { "Привлекает трёх экспертов, получает их мнения и синтезирует вывод" }
    override var temperature: Double { 0.5 }
    override var maxTokens: Int { 2000 }

    init(sendMessage: any SendMessageToLMMUseCase, persistence: ConversationPersistenceService) {
        super.init(
            sendMessage: sendMessage,
            persistence: persistence,
            systemPrompt: """
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
                """,
            persistenceKey: "multi_expert_agent"
        )
    }
}
