import Foundation

/// Represents a parsed .env file.
struct EnvFile: Equatable {
    let filePath: String
    let entries: [EnvEntry]
    let metadata: Metadata
    let isReadOnly: Bool

    var isDirty: Bool = false

    /// Key-value entries only (excludes comments, blanks, malformed).
    var keyValueEntries: [EnvEntry] {
        entries.filter { $0.type == .keyValue }
    }

    /// All unique keys in order of first appearance.
    var keys: [String] {
        var seen = Set<String>()
        return keyValueEntries.compactMap { entry in
            guard let key = entry.key, !seen.contains(key) else { return nil }
            seen.insert(key)
            return key
        }
    }

    /// Keys that appear more than once.
    var duplicateKeys: Set<String> {
        var counts: [String: Int] = [:]
        for entry in keyValueEntries {
            if let key = entry.key {
                counts[key, default: 0] += 1
            }
        }
        return Set(counts.filter { $0.value > 1 }.keys)
    }

    /// Total key count (unique).
    var keyCount: Int { keys.count }

    // MARK: - Warning Aggregation

    /// A file-level warning with context for display.
    struct FileWarning: Identifiable, Equatable {
        let id = UUID()
        let type: WarningType
        let message: String
        let lineNumber: Int? // nil for file-level warnings

        enum WarningType: String, Equatable {
            case bom = "BOM"
            case readOnly = "Read-Only"
            case unclosedQuote = "Unclosed Quote"
            case duplicateKey = "Duplicate Key"
            case nonStandardKey = "Non-Standard Key"
            case malformedLine = "Malformed Line"
        }

        static func == (lhs: FileWarning, rhs: FileWarning) -> Bool {
            lhs.type == rhs.type && lhs.message == rhs.message && lhs.lineNumber == rhs.lineNumber
        }
    }

    /// All warnings aggregated from file metadata and entry-level warnings.
    var allWarnings: [FileWarning] {
        var warnings: [FileWarning] = []

        // File-level warnings
        if metadata.hasBOM {
            warnings.append(FileWarning(type: .bom, message: "File has UTF-8 BOM", lineNumber: nil))
        }
        if isReadOnly {
            warnings.append(FileWarning(type: .readOnly, message: "File is read-only", lineNumber: nil))
        }

        // Entry-level warnings
        for entry in entries {
            for warning in entry.warnings {
                let type: FileWarning.WarningType
                let message: String
                switch warning {
                case .unclosedQuote:
                    type = .unclosedQuote
                    message = "Unclosed quote: \(entry.key ?? entry.rawLine)"
                case .duplicateKey:
                    type = .duplicateKey
                    message = "Duplicate key: \(entry.key ?? "unknown")"
                case .nonStandardKey:
                    type = .nonStandardKey
                    message = "Non-standard key: \(entry.key ?? "unknown")"
                case .malformedLine:
                    type = .malformedLine
                    message = "Malformed: \(entry.rawLine.prefix(40))"
                }
                warnings.append(FileWarning(type: type, message: message, lineNumber: entry.lineNumber))
            }
        }

        return warnings
    }

    struct Metadata: Equatable {
        let hasBOM: Bool
        let originalLineEnding: LineEnding
        let encoding: String.Encoding

        enum LineEnding: Equatable {
            case lf      // \n (Unix)
            case crlf    // \r\n (Windows)
            case cr      // \r (old Mac)
        }
    }
}
