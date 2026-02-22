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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ForEach(ProviderType.allCases, id: \.self) { provider in
                    Button {
                        modelStore.selectedProvider = provider
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") {
                    dismiss()
                }
            }
        }
    }
}
