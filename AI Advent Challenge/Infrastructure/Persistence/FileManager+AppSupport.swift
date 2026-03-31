//
//  FileManager+AppSupport.swift
//  AI Advent Challenge
//

import Foundation

extension FileManager {
    /// Returns the Application Support directory for the current user, or `nil` if unavailable.
    ///
    /// On iOS/macOS this directory is always present, but returning `nil` allows callers to
    /// handle edge cases gracefully (e.g. unit tests with a custom sandbox).
    var appSupportDirectory: URL? {
        urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }
}
