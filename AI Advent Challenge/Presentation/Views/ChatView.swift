//
//  ChatView.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @State private var highlightedChip: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    // System prompt header
                    if !viewModel.systemPrompt.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.systemPrompt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .id("systemPrompt")
                    }
                    
                    // Messages list
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                                .contextMenu {
                                    if message.role == .assistant,
                                       viewModel.agentType == .promptCrafter {
                                        Button {
                                            viewModel.useAsCustomAgentPrompt(message.content)
                                        } label: {
                                            Label("Использовать как системный промпт",
                                                  systemImage: "text.badge.checkmark")
                                        }
                                    }
                                }
                        }

                        if viewModel.isLoading {
                            HStack {
                                ProgressView()
                                Text("Думаю...")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .id("thinking")
                        }
                    }
                    .padding()
                }
                .onAppear {
                    proxy.scrollTo("systemPrompt", anchor: .top)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let lastMessage = viewModel.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: viewModel.isLoading) { _, isLoading in
                    if isLoading {
                        withAnimation {
                            proxy.scrollTo("thinking", anchor: .bottom)
                        }
                    }
                }
            }

            // Error display
            if let error = viewModel.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }

            // Message history chips
            if !viewModel.historyStore.items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.historyStore.items, id: \.self) { msg in
                            HStack(spacing: 4) {
                                Button {
                                    viewModel.inputText = msg
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        viewModel.historyStore.add(msg)
                                        highlightedChip = msg
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            highlightedChip = nil
                                        }
                                    }
                                } label: {
                                    Text(msg)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .frame(maxWidth: UIScreen.main.bounds.width * 0.55, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    viewModel.historyStore.remove(msg)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                highlightedChip == msg
                                    ? Color.accentColor.opacity(0.15)
                                    : Color(uiColor: .secondarySystemBackground)
                            )
                            .clipShape(Capsule())
                            .drawingGroup()
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }

            // Input field
            HStack(spacing: 12) {
                TextField("Введите сообщение...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)
                    .onSubmit {
                        viewModel.sendMessage()
                    }

                Button(action: viewModel.sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                }
                .disabled(viewModel.inputText.isEmpty || viewModel.isLoading)
            }
            .padding()
            .background(Color(uiColor: .systemBackground))
        }
        .navigationBarTitleDisplayMode(.inline)
    }

}
