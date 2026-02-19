//
//  TemperatureStore.swift
//  AI Advent Challenge
//
//  Created by Claude on 19.02.2026.
//

import Combine

@MainActor
final class TemperatureStore: ObservableObject {
    @Published var temperature: Double = 0.7

    static let range: ClosedRange<Float> = 0.0...2.0
}
