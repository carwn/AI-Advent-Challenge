//
//  ChatViewModel.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var error: String?

    private let sendMessageUseCase: SendMessageUseCase
    private var conversationId: UUID!
    private var cancellables = Set<AnyCancellable>()

    init(
        sendMessageUseCase: SendMessageUseCase,
        conversation: Conversation
    ) {
        self.sendMessageUseCase = sendMessageUseCase
        setup(conversation)
    }
    
    func setup(_ conversation: Conversation) {
        self.conversationId = conversation.id
        self.messages = conversation.messages.filter { $0.role != .system }
    }

    func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let messageText = inputText
        inputText = ""
        isLoading = true
        error = nil

        // Add user message immediately
        let userMessage = Message(role: .user, content: messageText)
        messages.append(userMessage)

        Task {
            do {
                let response = try await sendMessageUseCase.execute(
                    message: messageText,
                    conversationId: conversationId
                )

                messages.append(response.message)
                isLoading = false
            } catch {
                self.error = error.localizedDescription
                isLoading = false
            }
        }
    }
}
