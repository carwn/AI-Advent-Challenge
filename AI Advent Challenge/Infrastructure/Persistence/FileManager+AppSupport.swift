//
//  FileManager+AppSupport.swift
//  AI Advent Challenge
//

import Foundation

extension FileManager {
    /// Returns the Application Support directory for the current user, or `nil` if unavailable.
    var appSupportDirectory: URL? {
        urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    /// Returns the `AgentState` directory used for persisting agent data, creating it if needed.
    ///
    /// Falls back to a subdirectory of `NSTemporaryDirectory()` when Application Support
    /// is unavailable (e.g. unit tests with a custom sandbox), logging a warning so the
    /// degraded mode is visible during debugging.
    func agentStateDirectory() -> URL {
        let base: URL
        if let appSupport = appSupportDirectory {
            base = appSupport
        } else {
            print("[FileManager] Warning: Application Support directory unavailable — " +
                  "falling back to NSTemporaryDirectory(). State will NOT persist across launches.")
            base = URL(fileURLWithPath: NSTemporaryDirectory())
        }
        let dir = base.appendingPathComponent("AgentState", isDirectory: true)
        try? createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
