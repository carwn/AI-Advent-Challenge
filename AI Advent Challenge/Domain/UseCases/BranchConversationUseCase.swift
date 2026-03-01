//
//  BranchConversationUseCase.swift
//  AI Advent Challenge
//

import Foundation

protocol BranchConversationUseCase {
    func branch(record: ConversationRecord) -> ConversationRecord
}

final class BranchConversationInteractor: BranchConversationUseCase {
    private let persistence: ConversationPersistenceService

    init(persistence: ConversationPersistenceService) {
        self.persistence = persistence
    }

    func branch(record: ConversationRecord) -> ConversationRecord {
        let newId = UUID()
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM, HH:mm"
        formatter.locale = Locale(identifier: "ru_RU")

        let branchedRecord = ConversationRecord(
            id: newId,
            agentKey: record.agentKey,
            agentName: record.agentName,
            agentIcon: record.agentIcon,
            title: "↳ \(record.title)",
            lastMessagePreview: record.lastMessagePreview,
            lastMessageDate: record.lastMessageDate,
            createdAt: Date(),
            parentId: record.id
        )

        persistence.copyConversation(from: record.id.uuidString, to: newId.uuidString)
        persistence.copyPolicyCaches(from: record.id.uuidString, to: newId.uuidString)
        persistence.saveRecord(branchedRecord)

        return branchedRecord
    }
}
