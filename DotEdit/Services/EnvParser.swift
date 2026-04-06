import Foundation

/// Parses raw .env file content into an array of `EnvEntry` values.
enum EnvParser {

    /// Parse raw file content into an `EnvFile`.
    static func parse(content: String, filePath: String) -> EnvFile {
        let metadata = detectMetadata(content)
        let cleanContent = stripBOM(content)
        let lines = splitLines(cleanContent)
        var entries = lines.enumerated().map { index, line in
            parseLine(line, lineNumber: index + 1)
        }

        // Mark duplicate keys
        entries = markDuplicates(entries)

        return EnvFile(
            filePath: filePath,
            entries: entries,
            metadata: metadata,
            isReadOnly: false
        )
    }

    // MARK: - Metadata Detection

    static func detectMetadata(_ content: String) -> EnvFile.Metadata {
        let hasBOM = content.hasPrefix("\u{FEFF}")
        let lineEnding = detectLineEnding(content)
        return EnvFile.Metadata(
            hasBOM: hasBOM,
            originalLineEnding: lineEnding,
            encoding: .utf8
        )
    }

    static func detectLineEnding(_ content: String) -> EnvFile.Metadata.LineEnding {
        if content.contains("\r\n") { return .crlf }
        if content.contains("\r") { return .cr }
        return .lf
    }

    // MARK: - BOM

    static func stripBOM(_ content: String) -> String {
        if content.hasPrefix("\u{FEFF}") {
            return String(content.dropFirst())
        }
        return content
    }

    // MARK: - Line Splitting (normalize to \n)

    static func splitLines(_ content: String) -> [String] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Handle multiline values — join lines inside open quotes
        return resolveMultilineValues(normalized.components(separatedBy: "\n"))
    }

    // MARK: - Multiline Resolution

    /// Joins lines that are part of a multiline quoted value.
    /// A multiline value starts when a quote opens and doesn't close on the same line.
    /// Maximum continuation lines per multiline entry to prevent memory spikes from unclosed quotes.
    static let maxLinesPerEntry = 500

    static func resolveMultilineValues(_ rawLines: [String]) -> [String] {
        var result: [String] = []
        var accumulator: String?
        var openQuote: Character?
        var accumulatedLineCount = 0

        for line in rawLines {
            if let acc = accumulator, let quote = openQuote {
                accumulatedLineCount += 1
                // We're inside a multiline value — append this line
                let joined = acc + "\n" + line
                if lineClosesQuote(line, quote: quote) {
                    result.append(joined)
                    accumulator = nil
                    openQuote = nil
                    accumulatedLineCount = 0
                } else if accumulatedLineCount >= maxLinesPerEntry {
                    // Guard: emit as-is to prevent memory spikes from unclosed quotes
                    result.append(joined)
                    accumulator = nil
                    openQuote = nil
                    accumulatedLineCount = 0
                } else {
                    accumulator = joined
                }
            } else {
                // Check if this line opens a multiline value
                if let quote = lineOpensUnclosedQuote(line) {
                    accumulator = line
                    openQuote = quote
                } else {
                    result.append(line)
                }
            }
        }

        // If we hit EOF with an unclosed quote, emit what we have
        if let acc = accumulator {
            result.append(acc)
        }

        return result
    }

    /// Returns the quote character if the line opens a quoted value that doesn't close.
    static func lineOpensUnclosedQuote(_ line: String) -> Character? {
        guard let eqIndex = line.firstIndex(of: "=") else { return nil }
        let afterEq = String(line[line.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)

        // Strip export prefix for detection
        let keyPart = String(line[..<eqIndex]).trimmingCharacters(in: .whitespaces)
        let strippedKey = keyPart.hasPrefix("export ") || keyPart.hasPrefix("export\t")
            ? String(keyPart.dropFirst(7)).trimmingCharacters(in: .whitespaces)
            : keyPart

        // Only check if this looks like a key=value line
        guard !strippedKey.isEmpty, !strippedKey.hasPrefix("#") else { return nil }

        guard let firstChar = afterEq.first,
              firstChar == "\"" || firstChar == "'" || firstChar == "`" else {
            return nil
        }

        // Check if the quote closes on the same line
        let valueContent = String(afterEq.dropFirst())
        if valueContent.contains(firstChar) {
            // Quote closes on the same line — not multiline
            return nil
        }

        return firstChar
    }

    /// Checks if a line ends with the closing quote for an open multiline value.
    static func lineClosesQuote(_ line: String, quote: Character) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return false }
        return last == quote
    }

    // MARK: - Line Parsing

    static func parseLine(_ line: String, lineNumber: Int) -> EnvEntry {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Blank line
        if trimmed.isEmpty {
            return EnvEntry(
                lineNumber: lineNumber,
                rawLine: line,
                type: .blank,
                key: nil,
                value: nil,
                hasExportPrefix: false,
                quoteStyle: .none,
                warnings: []
            )
        }

        // Comment line
        if trimmed.hasPrefix("#") {
            return EnvEntry(
                lineNumber: lineNumber,
                rawLine: line,
                type: .comment,
                key: nil,
                value: nil,
                hasExportPrefix: false,
                quoteStyle: .none,
                warnings: []
            )
        }

        // Try to parse as key=value
        guard let eqIndex = trimmed.firstIndex(of: "=") else {
            // No = sign → malformed
            return EnvEntry(
                lineNumber: lineNumber,
                rawLine: line,
                type: .malformed,
                key: nil,
                value: nil,
                hasExportPrefix: false,
                quoteStyle: .none,
                warnings: [.malformedLine]
            )
        }

        // Split on first =
        var keyPart = String(trimmed[..<eqIndex]).trimmingCharacters(in: .whitespaces)
        let valuePart = String(trimmed[trimmed.index(after: eqIndex)...])

        // Detect export prefix
        let hasExport = keyPart.hasPrefix("export ") || keyPart.hasPrefix("export\t")
        if hasExport {
            keyPart = String(keyPart.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        }

        // Parse value and quote style
        let (parsedValue, quoteStyle, warnings) = parseValue(valuePart)

        // Check for non-standard key characters
        var allWarnings = warnings
        if !isStandardKey(keyPart) {
            allWarnings.append(.nonStandardKey)
        }

        return EnvEntry(
            lineNumber: lineNumber,
            rawLine: line,
            type: .keyValue,
            key: keyPart,
            value: parsedValue,
            hasExportPrefix: hasExport,
            quoteStyle: quoteStyle,
            warnings: allWarnings
        )
    }

    // MARK: - Value Parsing

    /// Parses the value portion (after `=`), detecting quote style and unclosed quotes.
    static func parseValue(_ raw: String) -> (String, EnvEntry.QuoteStyle, [EnvEntry.Warning]) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        // Empty value
        if trimmed.isEmpty {
            return ("", .none, [])
        }

        // Check for quoted value
        let firstChar = trimmed.first!
        if firstChar == "\"" || firstChar == "'" || firstChar == "`" {
            let quoteStyle: EnvEntry.QuoteStyle = switch firstChar {
            case "\"": .double
            case "'": .single
            default: .backtick
            }

            let afterOpen = String(trimmed.dropFirst())

            // Find closing quote
            if let closeIndex = afterOpen.firstIndex(of: firstChar) {
                // Properly closed quote
                let innerValue = String(afterOpen[..<closeIndex])
                return (innerValue, quoteStyle, [])
            } else {
                // Unclosed quote — value is everything after the opening quote
                // (multiline values will have been joined already by resolveMultilineValues,
                //  so if we still can't find closing quote, it's truly unclosed)
                if afterOpen.contains("\n") {
                    // Multiline — check if closing quote is on a later line
                    if let closeIndex = afterOpen.lastIndex(of: firstChar) {
                        let innerValue = String(afterOpen[..<closeIndex])
                        return (innerValue, quoteStyle, [])
                    }
                }
                return (afterOpen, quoteStyle, [.unclosedQuote])
            }
        }

        // Unquoted value — entire remainder is the value (including inline # comments per dotenv spec)
        return (trimmed, .none, [])
    }

    // MARK: - Key Validation

    /// Standard .env key: starts with letter or underscore, contains only [A-Za-z0-9_].
    static func isStandardKey(_ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        let pattern = /^[A-Za-z_][A-Za-z0-9_]*$/
        return key.wholeMatch(of: pattern) != nil
    }

    // MARK: - Duplicate Detection

    static func markDuplicates(_ entries: [EnvEntry]) -> [EnvEntry] {
        // Count occurrences of each key
        var keyCounts: [String: Int] = [:]
        for entry in entries where entry.type == .keyValue {
            if let key = entry.key {
                keyCounts[key, default: 0] += 1
            }
        }

        let duplicateKeys = Set(keyCounts.filter { $0.value > 1 }.keys)
        guard !duplicateKeys.isEmpty else { return entries }

        return entries.map { entry in
            guard entry.type == .keyValue,
                  let key = entry.key,
                  duplicateKeys.contains(key),
                  !entry.warnings.contains(.duplicateKey) else {
                return entry
            }
            var warnings = entry.warnings
            warnings.append(.duplicateKey)
            return EnvEntry(
                lineNumber: entry.lineNumber,
                rawLine: entry.rawLine,
                type: entry.type,
                key: entry.key,
                value: entry.value,
                hasExportPrefix: entry.hasExportPrefix,
                quoteStyle: entry.quoteStyle,
                warnings: warnings
            )
        }
    }

    // MARK: - Binary Detection

    /// Returns true if the content appears to be binary (contains null bytes).
    static func isBinaryContent(_ data: Data) -> Bool {
        data.contains(0x00)
    }

    // MARK: - Serialization

    /// Converts entries back to raw string content.
    static func serialize(entries: [EnvEntry], lineEnding: EnvFile.Metadata.LineEnding = .lf) -> String {
        let separator: String = switch lineEnding {
        case .lf: "\n"
        case .crlf: "\r\n"
        case .cr: "\r"
        }
        return entries.map(\.rawLine).joined(separator: separator)
    }
}
