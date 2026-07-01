// Log.swift — os.Logger namespace with category channels.

import Foundation
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.piercemoore.vibe"

    static let app     = Logger(subsystem: subsystem, category: "app")
    static let scan    = Logger(subsystem: subsystem, category: "scan")
    static let git     = Logger(subsystem: subsystem, category: "git")
    static let ui      = Logger(subsystem: subsystem, category: "ui")
    static let process = Logger(subsystem: subsystem, category: "process")
}
