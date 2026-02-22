//
//  ModelStore.swift
//  AI Advent Challenge
//
//  Created by Claude on 22.02.2026.
//

import Foundation
import Combine

@MainActor
final class ModelStore: ObservableObject {
    @Published var selectedProvider: ProviderType {
        didSet {
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: "selectedProvider")
        }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: "selectedProvider") ?? ""
        self.selectedProvider = ProviderType(rawValue: saved) ?? .gpt41Mini
    }
}
