//
//  SettingsView.swift
//  AI Advent Challenge
//
//  Created by Claude on 16.02.2026.
//

import SwiftUI

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
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
