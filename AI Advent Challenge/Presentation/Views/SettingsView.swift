//
//  SettingsView.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import SwiftUI

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel
    @ObservedObject var modelStore: ModelStore
    @ObservedObject var longTermMemoryStore: LongTermMemoryStore
    @Environment(\.dismiss) private var dismiss
    var onAllDataCleared: (() -> Void)?

    @State private var showingClearAllAlert = false

    var body: some View {
        Form {
            Section {
                ForEach(ProviderType.allCases, id: \.self) { provider in
                    Button {
                        modelStore.selectedProvider = provider
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.displayName)
                                    .foregroundStyle(.primary)
                                let p = provider.pricingRUB
                                Text("↑\(Int(p.input))₽  ↓\(Int(p.output))₽  / 1М токенов")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if modelStore.selectedProvider == provider {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("LLM Провайдер")
            } footer: {
                Text("Все модели доступны через ProxyAPI.ru с единым API-ключом.")
                    .font(.caption)
            }

            Section {
                SecureField("API-ключ", text: $viewModel.openAIKey)
                    .textContentType(.password)

                Button("Сохранить API-ключ") {
                    viewModel.saveAPIKey()
                }
                .disabled(viewModel.openAIKey.isEmpty)

                Button("Удалить API-ключ", role: .destructive) {
                    viewModel.deleteAPIKey()
                }
                .disabled(viewModel.openAIKey.isEmpty)
            } header: {
                Text("Настройка ProxyAPI.ru")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ваш API-ключ хранится в Keychain и никуда не передаётся.")
                        .font(.caption)
                    Text("Получить ключ: https://proxyapi.ru")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }

            Section {
                TextEditor(text: $longTermMemoryStore.text)
                    .frame(minHeight: 140)

                Button("Сохранить") {
                    viewModel.saveLongTermMemory()
                }

                Button("Очистить", role: .destructive) {
                    longTermMemoryStore.text = ""
                    longTermMemoryStore.save()
                }
                .disabled(longTermMemoryStore.text.isEmpty)
            } header: {
                Text("Долговременная память")
            } footer: {
                Text("Текст доступен агенту «Тройная память» в каждом разговоре.")
                    .font(.caption)
            }

            Section {
                SecureField("Tavily API-ключ", text: $viewModel.tavilyKey)
                    .textContentType(.password)

                Button("Сохранить ключ Tavily") {
                    viewModel.saveTavilyKey()
                }
                .disabled(viewModel.tavilyKey.isEmpty)

                Button("Удалить ключ Tavily", role: .destructive) {
                    viewModel.deleteTavilyKey()
                }
                .disabled(viewModel.tavilyKey.isEmpty)
            } header: {
                Text("MCP серверы")
            } footer: {
                Text("Ключ используется для подключения к Tavily MCP. Carwn MCP не требует авторизации.")
                    .font(.caption)
            }

            Section {
                Button("Очистить все данные", role: .destructive) {
                    showingClearAllAlert = true
                }
            } header: {
                Text("Опасная зона")
            } footer: {
                Text("Удаляет все диалоги, кэши политик сжатия и долговременную память.")
                    .font(.caption)
            }

            if let error = viewModel.error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Настройки")
        .alert("Очистить все данные?", isPresented: $showingClearAllAlert) {
            Button("Очистить", role: .destructive) {
                viewModel.clearAllData()
                dismiss()
                onAllDataCleared?()
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Все диалоги и кэши будут безвозвратно удалены.")
        }
        .alert("Готово", isPresented: $viewModel.showingSaveSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("API-ключ сохранён")
        }
        .alert("Сохранено", isPresented: $viewModel.showingMemorySaveSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Долговременная память обновлена")
        }
        .alert("Готово", isPresented: $viewModel.showingTavilySaveSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Tavily API-ключ сохранён")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") {
                    dismiss()
                }
            }
        }
    }
}
