//
//  ContentView.swift
//  AI Advent Challenge
//
//  Created by Александр Шелихов on 16.02.2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var records: [ConversationRecord] = []
    @State private var chatViewModel: ChatViewModel?
    @State private var isShowingChat = false
    @State private var showingNewConversation = false
    @State private var showingSettings = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "Нет диалогов",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Нажмите + чтобы начать новый диалог")
                    )
                } else {
                    List {
                        ForEach(recordsSorted) { record in
                            Button {
                                openChat(record: record)
                            } label: {
                                ConversationRow(record: record)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) {
                                Button {
                                    let branch = container.branchConversation.branch(record: record)
                                    loadRecords()
                                    openChat(record: branch)
                                } label: {
                                    Label("Ветка", systemImage: "arrow.branch")
                                }
                                .tint(.green)
                            }
                        }
                        .onDelete { indexSet in
                            indexSet.forEach { i in
                                let record = recordsSorted[i]
                                container.conversationPersistence.deleteRecord(id: record.id)
                                container.conversationPersistence.delete(forKey: record.id.uuidString)
                            }
                            loadRecords()
                        }
                    }
                }
            }
            .navigationTitle("Диалоги")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNewConversation = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .navigationDestination(isPresented: $isShowingChat) {
                if let vm = chatViewModel {
                    ChatView(viewModel: vm)
                }
            }
            .sheet(isPresented: $showingNewConversation) {
                AgentSelectionView(
                    viewModel: container.makeAgentSelectionViewModel(),
                    onAgentSelected: { template in
                        showingNewConversation = false
                        guard let record = container.createConversation(agentKey: template.id) else { return }
                        openChat(record: record)
                    }
                )
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    SettingsView(
                        viewModel: container.makeSettingsViewModel(),
                        modelStore: container.modelStore,
                        longTermMemoryStore: container.longTermMemoryStore
                    )
                }
            }
            .task { loadRecords() }
            .onAppear { loadRecords() }
            .onChange(of: container.modelStore.selectedProvider) { _, _ in
                isShowingChat = false
                chatViewModel = nil
                loadRecords()
            }
            .alert("Требуется настройка", isPresented: $showingError) {
                Button("Открыть настройки") { showingSettings = true }
                Button("Отмена", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Helpers

    private var recordsSorted: [ConversationRecord] {
        let byDate: (ConversationRecord, ConversationRecord) -> Bool = {
            ($0.lastMessageDate ?? $0.createdAt) > ($1.lastMessageDate ?? $1.createdAt)
        }

        func children(of id: UUID) -> [ConversationRecord] {
            records
                .filter { $0.parentId == id }
                .sorted(by: byDate)
                .flatMap { child in [child] + children(of: child.id) }
        }

        let allIds = Set(records.map { $0.id })
        let roots = records
            .filter { record in
                guard let pid = record.parentId else { return true }
                return !allIds.contains(pid) // осиротевшая ветка становится корнем
            }
            .sorted(by: byDate)

        return roots.flatMap { root in [root] + children(of: root.id) }
    }

    private func loadRecords() {
        records = container.conversationPersistence.loadRecords()
    }

    private func openChat(record: ConversationRecord) {
        do {
            let agent = try container.makeAgent(record: record)
            chatViewModel = container.makeChatViewModel(agent: agent)
            isShowingChat = true
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - Conversation row

private struct ConversationRow: View {
    let record: ConversationRecord

    var body: some View {
        HStack(spacing: .zero) {
            HStack(spacing: 12) {
                if record.parentId != nil {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .frame(width: 12)
                }

                Image(systemName: record.agentIcon)
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                    .frame(width: 40)

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.title)
                        .font(.headline)
                        .lineLimit(2)

                    Text(record.lastMessagePreview ?? "Нет сообщений")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    HStack(spacing: 4) {
                        Text(record.agentName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        if record.parentId != nil {
                            Text("· ветка")
                                .font(.caption2)
                                .foregroundStyle(.green.opacity(0.8))
                        }
                    }
                }
            }
            
            Spacer(minLength: 16)

            let date = record.lastMessageDate ?? record.createdAt
            TimelineView(.everyMinute) { _ in
                Text(relativeDate(date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
    }
}

private func relativeDate(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    guard interval >= 60 else { return "только что" }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
}
