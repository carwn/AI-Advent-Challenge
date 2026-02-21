//
//  ContentView.swift
//  AI Advent Challenge
//
//  Created by Александр Шелихов on 16.02.2026.
//

import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var showingAgentSelection = false
    @State private var showingSettings = false
    @State private var selectedConversation: Conversation?
    @State private var chatViewModel: ChatViewModel?
    @State private var chatViewModelCache: [AgentType: ChatViewModel] = [:]
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel = chatViewModel {
                    ChatView(viewModel: viewModel)
                } else {
                    welcomeView
                }
            }
            .navigationTitle("AI Ассистент")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if let selectedAgentType = selectedConversation?.agentType,
                       let vm = chatViewModel {
                        NavigationTitleView(
                            agentType: selectedAgentType,
                            chatViewModel: vm,
                            onTap: { showingAgentSelection = true }
                        )
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let vm = chatViewModel {
                        Button(role: .destructive) {
                            vm.clearConversation()
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .disabled(vm.isLoading)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .font(.caption)
                    }
                }
            }
            .sheet(isPresented: $showingAgentSelection) {
                AgentSelectionView(
                    viewModel: container.makeAgentSelectionViewModel(),
                    onAgentSelected: { conversation in
                        handleAgentSelection(conversation)
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
            .alert("Требуется настройка", isPresented: $showingError) {
                Button("Открыть настройки") {
                    showingSettings = true
                }
                Button("Отмена", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .onReceive(container.modelStore.objectWillChange) { _ in
                chatViewModelCache = [:]
                chatViewModel = nil
                selectedConversation = nil
            }
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain")
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            Text("AI Ассистент")
                .font(.title)
                .fontWeight(.bold)

            Text("Выберите агента для начала")
                .foregroundStyle(.secondary)

            Button("Выбрать агента") {
                showingAgentSelection = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func handleAgentSelection(_ conversation: Conversation) {
        selectedConversation = conversation
        showingAgentSelection = false
        if let cached = chatViewModelCache[conversation.agentType] {
            chatViewModel = cached
        } else {
            do {
                let viewModel = try container.makeChatViewModel(conversation: conversation)
                chatViewModelCache[conversation.agentType] = viewModel
                chatViewModel = viewModel
            } catch {
                errorMessage = error.localizedDescription
                showingError = true
            }
        }
    }
}

private struct NavigationTitleView: View {
    let agentType: AgentType
    @ObservedObject var chatViewModel: ChatViewModel
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button(action: onTap) {
                HStack(spacing: 4) {
                    Image(systemName: agentType.icon)
                        .font(.callout)
                    Text(agentType.rawValue)
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            (
                Text("↑").foregroundStyle(.blue) +
                Text("\(chatViewModel.totalPromptTokens) ").foregroundStyle(.secondary) +
                Text("↓").foregroundStyle(.orange) +
                Text("\(chatViewModel.totalCompletionTokens)").foregroundStyle(.secondary)
            )
            .font(.caption2.monospaced())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
