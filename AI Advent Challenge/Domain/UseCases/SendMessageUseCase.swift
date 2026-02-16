//
//  SendMessageUseCase.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation

final class SendMessageUseCase {
    private let agent: Agent
    private let repository: ConversationRepository

    init(agent: Agent, repository: ConversationRepository) {
        self.agent = agent
        self.repository = repository
    }

    func execute(
        message: String,
        conversationId: UUID
    ) async throws -> AgentResponse {
        var conversation = repository.getConversation(id: conversationId)
        conversation.addMessage(Message(role: .user, content: message))
        repository.updateConversation(conversation)

        // Send initial message
        var response = try await agent.sendMessage(message, in: conversation)
        conversation.addMessage(response.message)

        // Execute tools if needed and continue
        if response.requiresToolExecution {
            do {
                response = try await agent.executeToolsAndContinue(response, in: conversation)
                conversation.addMessage(response.message)
            } catch {
                conversation.addMessage(Message(role: .system, content: "Ошибка вызова инстумента"))
            }
        }
        repository.updateConversation(conversation)
        
        return response
    }
}
