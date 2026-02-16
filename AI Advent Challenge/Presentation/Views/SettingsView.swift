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
                SecureField("API Key", text: $viewModel.openAIKey)
                    .textContentType(.password)

                Button("Save API Key") {
                    viewModel.saveAPIKey()
                }
                .disabled(viewModel.openAIKey.isEmpty)

                Button("Delete API Key", role: .destructive) {
                    viewModel.deleteAPIKey()
                }
                .disabled(viewModel.openAIKey.isEmpty)
            } header: {
                Text("ProxyAPI.ru Configuration")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your API key is stored securely in the Keychain and never shared.")
                        .font(.caption)
                    Text("Get your key from: https://proxyapi.ru")
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
        .navigationTitle("Settings")
        .alert("Success", isPresented: $viewModel.showingSaveSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("API key saved successfully")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }
}
