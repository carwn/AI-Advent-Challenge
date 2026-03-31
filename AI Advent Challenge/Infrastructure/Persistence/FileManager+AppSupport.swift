//
//  FileManager+AppSupport.swift
//  AI Advent Challenge
//

import Foundation

extension FileManager {
    /// Returns the Application Support directory for the current user.
    ///
    /// On iOS/macOS this directory always exists, so a missing URL is treated as a programmer error.
    var appSupportDirectory: URL {
        guard let url = urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not found — this should never happen on iOS/macOS")
        }
        return url
    }
}
