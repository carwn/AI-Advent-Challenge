//
//  AI_Advent_ChallengeApp.swift
//  AI Advent Challenge
//
//  Created by Александр Шелихов on 16.02.2026.
//

import SwiftUI

@main
struct AI_Advent_ChallengeApp: App {
    @StateObject private var container = DependencyContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container)
        }
    }
}
