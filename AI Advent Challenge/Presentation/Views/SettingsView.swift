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

            if let error = viewModel.error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Настройки")
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") {
                    dismiss()
                }
            }
        }
    }
}
