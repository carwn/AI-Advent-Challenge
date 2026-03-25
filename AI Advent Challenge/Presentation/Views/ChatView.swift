//
//  ChatView.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @EnvironmentObject var container: DependencyContainer
    @FocusState private var isInputFocused: Bool
    @State private var highlightedChip: String?
    @State private var chipsContainerWidth: CGFloat = 300
    @State private var showRAGModeSheet = false
    @State private var isAtBottom = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    // Messages list
                    VStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }

                        if viewModel.isLoading {
                            HStack {
                                ProgressView()
                                Text("Думаю...")
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }

                        // Невидимый якорь для скролла вниз
                        Color.clear.frame(height: 1).id("_bottom")
                    }
                    .padding()
                }
                // Отслеживаем, находится ли скролл у нижнего края (порог 50pt)
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height < 50
                } action: { _, atBottom in
                    isAtBottom = atBottom
                }
                .onAppear {
                    proxy.scrollTo("_bottom", anchor: .bottom)
                }
                // Во время стриминга скроллим только если пользователь не прокрутил вверх
                .onChange(of: viewModel.messages) { _, _ in
                    if isAtBottom {
                        proxy.scrollTo("_bottom", anchor: .bottom)
                    }
                }
                // При отправке нового сообщения всегда скроллим вниз
                .onChange(of: viewModel.isLoading) { _, isLoading in
                    if isLoading {
                        isAtBottom = true
                        proxy.scrollTo("_bottom", anchor: .bottom)
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
                                        .frame(maxWidth: chipsContainerWidth * 0.55, alignment: .leading)
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
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { chipsContainerWidth = geo.size.width }
                            .onChange(of: geo.size.width) { _, w in chipsContainerWidth = w }
                    }
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                ChatNavigationTitleView(viewModel: viewModel, modelStore: container.modelStore)
            }
            if viewModel.isRAGAgent {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showRAGModeSheet = true } label: {
                        HStack(spacing: 2) {
                            Image(systemName: viewModel.ragMode == .off ? "book.closed" : "book.pages")
                                .foregroundStyle(ragModeColor(viewModel.ragMode))
                            if viewModel.ragMode != .off {
                                Text(viewModel.ragMode.rawValue)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(ragModeColor(viewModel.ragMode))
                            }
                        }
                    }
                    .disabled(viewModel.isLoading)
                    .confirmationDialog("Режим RAG", isPresented: $showRAGModeSheet, titleVisibility: .visible) {
                        ForEach(RAGMode.allCases, id: \.self) { mode in
                            Button(ragModeLabel(mode)) {
                                viewModel.setRAGMode(mode)
                            }
                        }
                        Button("Отмена", role: .cancel) {}
                    } message: {
                        Text("Текущий режим: \(viewModel.ragMode.displayName)")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    viewModel.clearConversation()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.isLoading || viewModel.messages.isEmpty)
            }
        }
    }
}

// MARK: - RAG helpers

private func ragModeColor(_ mode: RAGMode) -> Color {
    switch mode {
    case .off:     return .secondary
    case .basic:   return .blue
    case .rerank:  return .orange
    case .rewrite: return .green
    case .full:    return .purple
    }
}

private func ragModeLabel(_ mode: RAGMode) -> String {
    switch mode {
    case .off:     return "off — RAG отключён"
    case .basic:   return "basic — top-3, cosine"
    case .rerank:  return "rerank — top-10 → MMR → top-3"
    case .rewrite: return "rewrite — query → English"
    case .full:    return "full — rewrite + rerank"
    }
}

// MARK: - Navigation title

private struct ChatNavigationTitleView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var modelStore: ModelStore

    private var inputCostRUB: Double {
        viewModel.messages.reduce(0.0) { sum, msg in
            guard let rawName = msg.modelName,
                  let provider = ProviderType(rawValue: rawName),
                  let tokens = msg.promptTokens else { return sum }
            return sum + Double(tokens) * provider.pricingRUB.input / 1_000_000
        }
    }

    private var outputCostRUB: Double {
        viewModel.messages.reduce(0.0) { sum, msg in
            guard let rawName = msg.modelName,
                  let provider = ProviderType(rawValue: rawName),
                  let tokens = msg.completionTokens else { return sum }
            let totalOutput = tokens + (msg.thoughtsTokens ?? 0)
            return sum + Double(totalOutput) * provider.pricingRUB.output / 1_000_000
        }
    }

    private var totalCostRUB: Double { inputCostRUB + outputCostRUB }

    private func fmt(_ v: Double) -> String {
        v < 0.01 ? String(format: "%.4f", v) : String(format: "%.2f", v)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: viewModel.agentIcon)
                    .font(.callout)
                Text(viewModel.agentName)
                    .font(.headline)
            }
            HStack(spacing: 4) {
                Text(modelStore.selectedProvider.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let policy = viewModel.agentCompressionPolicy {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(policy.description)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 6) {
                HStack(spacing: 0) {
                    Text("↑").foregroundStyle(.blue)
                    Text("\(viewModel.totalPromptTokens) ").foregroundStyle(.secondary)
                    Text("↓").foregroundStyle(.orange)
                    Text("\(viewModel.totalCompletionTokens)").foregroundStyle(.secondary)
                    let thoughts = viewModel.totalThoughtsTokens
                    if thoughts > 0 {
                        Text(" (+\(thoughts))").foregroundStyle(.purple)
                    }
                }
                .font(.caption2.monospaced())
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                HStack(spacing: 0) {
                    Text("↑").foregroundStyle(.blue)
                    Text("₽\(fmt(inputCostRUB)) ").foregroundStyle(.secondary)
                    Text("↓").foregroundStyle(.orange)
                    Text("₽\(fmt(outputCostRUB)) ").foregroundStyle(.secondary)
                    Text("∑").foregroundStyle(.secondary)
                    Text("₽\(fmt(totalCostRUB))").foregroundStyle(.green)
                }
                .font(.caption2.monospaced())
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
