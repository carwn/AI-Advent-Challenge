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
    @State private var showingTemperatureSlider = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    // System prompt header
                    if !viewModel.systemPrompt.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top) {
                                Text(viewModel.systemPrompt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showingTemperatureSlider.toggle()
                                    }
                                } label: {
                                    Text(String(format: "%.1f°", viewModel.temperatureStore.temperature))
                                        .font(.caption2.monospacedDigit())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(uiColor: .tertiarySystemBackground))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            if showingTemperatureSlider {
                                HStack(spacing: 8) {
                                    Image(systemName: "thermometer.low")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Slider(
                                        value: Binding(
                                            get: { Float(viewModel.temperatureStore.temperature) },
                                            set: { viewModel.temperatureStore.temperature = Double($0) }
                                        ),
                                        in: TemperatureStore.range,
                                        step: 0.1
                                    )
                                    Image(systemName: "thermometer.high")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
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
