import Foundation
import os

/// Centralized logging using Apple's unified logging system.
/// Debug-level messages appear in Xcode console and Console.app but are not persisted.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.dotedit"

    /// General app lifecycle events.
    static let general = Logger(subsystem: subsystem, category: "general")

    /// File I/O: loading, saving, watching.
    static let fileIO = Logger(subsystem: subsystem, category: "fileIO")

    /// File validation decisions.
    static let validation = Logger(subsystem: subsystem, category: "validation")

    /// Navigation and UI state changes.
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
