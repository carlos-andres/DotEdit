import Foundation

/// Represents a single line in an .env file.
struct EnvEntry: Identifiable, Equatable {
    let id = UUID()
    let lineNumber: Int
    let rawLine: String
    let type: EntryType

    // Populated for keyValue entries
    let key: String?
    let value: String?
    let hasExportPrefix: Bool
    let quoteStyle: QuoteStyle

    // Warnings
    let warnings: [Warning]

    enum EntryType: Equatable {
        case keyValue
        case comment
        case blank
        case malformed
    }

    enum QuoteStyle: Equatable {
        case none
        case single
        case double
        case backtick
    }

    enum Warning: Equatable {
        case unclosedQuote
        case duplicateKey
        case nonStandardKey
        case malformedLine
    }

    // MARK: - Multiline Helpers

    var isMultiline: Bool { rawLine.contains("\n") }
    var lineCount: Int { rawLine.components(separatedBy: "\n").count }

    // MARK: - Equatable (exclude id)

    static func == (lhs: EnvEntry, rhs: EnvEntry) -> Bool {
        lhs.lineNumber == rhs.lineNumber
            && lhs.rawLine == rhs.rawLine
            && lhs.type == rhs.type
            && lhs.key == rhs.key
            && lhs.value == rhs.value
            && lhs.hasExportPrefix == rhs.hasExportPrefix
            && lhs.quoteStyle == rhs.quoteStyle
            && lhs.warnings == rhs.warnings
    }
}
