//
//  FileManager+AppSupport.swift
//  AI Advent Challenge
//

import Foundation
import os.log

private let logger = Logger(subsystem: "com.aiapp", category: "persistence")

extension FileManager {
    /// Returns the Application Support directory for the current user, or `nil` if unavailable.
    var appSupportDirectory: URL? {
        urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    /// Returns the `AgentState` directory used for persisting agent data, creating it if needed.
    ///
    /// Falls back to a subdirectory of `NSTemporaryDirectory()` when Application Support
    /// is unavailable (e.g. unit tests with a custom sandbox). Both the fallback and any
    /// directory-creation failure are logged via `os.Logger` so degraded mode is visible
    /// in Console.app and Xcode's debug console.
    func agentStateDirectory() -> URL {
        let base: URL
        if let appSupport = appSupportDirectory {
            base = appSupport
        } else {
            logger.warning("Application Support directory unavailable — falling back to NSTemporaryDirectory(). State will NOT persist across launches.")
            base = URL(fileURLWithPath: NSTemporaryDirectory())
        }
        let dir = base.appendingPathComponent("AgentState", isDirectory: true)
        do {
            try createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create AgentState directory at \(dir.path): \(error.localizedDescription)")
        }
        return dir
    }
}
