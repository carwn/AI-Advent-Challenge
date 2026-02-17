//
//  ContentView.swift
//  AI Advent Challenge
//
//  Created by Александр Шелихов on 16.02.2026.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var container: DependencyContainer
    @State private var showingAgentSelection = false
    @State private var showingSettings = false
    @State private var selectedConversation: Conversation?
    @State private var chatViewModel: ChatViewModel?
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
            .navigationTitle("AI Assistant")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if let selectedAgentType = selectedConversation?.agentType {
                        Button {
                            showingAgentSelection = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: selectedAgentType.icon)
                                    .font(.callout)
                                Text(selectedAgentType.rawValue)
                                    .font(.headline)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gear")
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
                    SettingsView(viewModel: container.makeSettingsViewModel())
                }
            }
            .alert("Configuration Required", isPresented: $showingError) {
                Button("Open Settings") {
                    showingSettings = true
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 20) {
            Image(systemName: "brain")
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            Text("AI Agent Assistant")
                .font(.title)
                .fontWeight(.bold)

            Text("Select an agent to start")
                .foregroundStyle(.secondary)

            Button("Choose Agent") {
                showingAgentSelection = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func handleAgentSelection(_ conversation: Conversation) {
        selectedConversation = conversation
        showingAgentSelection = false
        do {
            let viewModel = try container.makeChatViewModel(conversation: conversation)
            chatViewModel = viewModel
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(DependencyContainer())
}
