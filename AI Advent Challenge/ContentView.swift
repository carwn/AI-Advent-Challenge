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
                        modelStore: container.modelStore
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
        records.sorted {
            ($0.lastMessageDate ?? $0.createdAt) > ($1.lastMessageDate ?? $1.createdAt)
        }
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
        HStack(spacing: 12) {
            Image(systemName: record.agentIcon)
                .font(.system(size: 28))
                .foregroundStyle(.blue)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(record.lastMessagePreview ?? "Нет сообщений")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(record.agentName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let date = record.lastMessageDate {
                    Text(date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(record.createdAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
