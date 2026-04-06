import Foundation

/// Computes key-based diffs between two `EnvFile` instances.
enum DiffEngine {

    /// How to handle `export` prefixed entries during diff.
    enum ExportMode: Equatable {
        /// Compare keys as-is including `export` prefix distinction.
        case preserve
        /// Strip `export ` prefix before comparing keys.
        case remove
        /// Exclude `export` lines from diff entirely.
        case skip
    }

    /// Key-based (default) or sequential (position-based) diff mode.
    enum DiffMode: Equatable { case keyBased, sequential }

    /// Options controlling diff behavior.
    struct Options {
        var caseInsensitiveKeys: Bool = false
        var exportMode: ExportMode = .preserve
        var diffMode: DiffMode = .keyBased

        static let `default` = Options()
    }

    /// Diff two env files and return categorized results.
    ///
    /// Results are ordered: matched pairs first (by left file order), then right-only entries.
    static func diff(left: EnvFile, right: EnvFile, options: Options = .default) -> [DiffResult] {
        if options.diffMode == .sequential {
            return sequentialDiff(left: left, right: right, options: options)
        }

        let leftEntries = filteredKeyValueEntries(from: left, options: options)
        let rightEntries = filteredKeyValueEntries(from: right, options: options)

        // Build lookup from right file: normalized key → first occurrence entry
        var rightLookup: [String: EnvEntry] = [:]
        var rightMatchedKeys: Set<String> = []
        for entry in rightEntries {
            let normKey = normalizedKey(for: entry, options: options)
            if rightLookup[normKey] == nil {
                rightLookup[normKey] = entry
            }
        }

        var results: [DiffResult] = []
        var leftSeenKeys: Set<String> = []

        // Walk left entries in order — match first occurrence of each key
        for entry in leftEntries {
            let normKey = normalizedKey(for: entry, options: options)

            // Duplicate key: only match first occurrence
            guard !leftSeenKeys.contains(normKey) else { continue }
            leftSeenKeys.insert(normKey)

            if let rightEntry = rightLookup[normKey] {
                // Matched pair
                rightMatchedKeys.insert(normKey)
                let leftValue = normalizedValue(for: entry)
                let rightValue = normalizedValue(for: rightEntry)

                if leftValue == rightValue {
                    results.append(DiffResult(category: .equal, leftEntry: entry, rightEntry: rightEntry))
                } else {
                    results.append(DiffResult(category: .modified, leftEntry: entry, rightEntry: rightEntry))
                }
            } else {
                // Left only
                results.append(DiffResult(category: .leftOnly, leftEntry: entry, rightEntry: nil))
            }
        }

        // Right-only entries (preserve right file order, first occurrence only)
        var rightSeenKeys: Set<String> = []
        for entry in rightEntries {
            let normKey = normalizedKey(for: entry, options: options)
            guard !rightSeenKeys.contains(normKey) else { continue }
            rightSeenKeys.insert(normKey)

            if !rightMatchedKeys.contains(normKey) {
                results.append(DiffResult(category: .rightOnly, leftEntry: nil, rightEntry: entry))
            }
        }

        return results
    }

    // MARK: - Sequential Diff

    /// Position-based diff: compare ALL entries (including comments/blanks) by index.
    private static func sequentialDiff(left: EnvFile, right: EnvFile, options: Options) -> [DiffResult] {
        let leftEntries = left.entries
        let rightEntries = right.entries
        let maxCount = max(leftEntries.count, rightEntries.count)

        var results: [DiffResult] = []

        for i in 0..<maxCount {
            let leftEntry = i < leftEntries.count ? leftEntries[i] : nil
            let rightEntry = i < rightEntries.count ? rightEntries[i] : nil

            if let l = leftEntry, let r = rightEntry {
                if entriesMatch(l, r, options: options) {
                    results.append(DiffResult(category: .equal, leftEntry: l, rightEntry: r))
                } else {
                    results.append(DiffResult(category: .modified, leftEntry: l, rightEntry: r))
                }
            } else if let l = leftEntry {
                results.append(DiffResult(category: .leftOnly, leftEntry: l, rightEntry: nil))
            } else if let r = rightEntry {
                results.append(DiffResult(category: .rightOnly, leftEntry: nil, rightEntry: r))
            }
        }

        return results
    }

    /// Check if two entries match for sequential comparison.
    private static func entriesMatch(_ left: EnvEntry, _ right: EnvEntry, options: Options) -> Bool {
        guard left.type == right.type else { return false }

        switch left.type {
        case .keyValue:
            let leftKey = normalizedKey(for: left, options: options)
            let rightKey = normalizedKey(for: right, options: options)
            guard leftKey == rightKey else { return false }
            return normalizedValue(for: left) == normalizedValue(for: right)

        case .comment, .blank, .malformed:
            return left.rawLine == right.rawLine
        }
    }

    // MARK: - Private Helpers

    /// Filter to key-value entries, applying export mode.
    private static func filteredKeyValueEntries(from file: EnvFile, options: Options) -> [EnvEntry] {
        file.keyValueEntries.filter { entry in
            if options.exportMode == .skip && entry.hasExportPrefix {
                return false
            }
            return true
        }
    }

    /// Normalize key for comparison based on options.
    private static func normalizedKey(for entry: EnvEntry, options: Options) -> String {
        guard var key = entry.key else { return "" }

        // In remove mode, the parser already strips "export " from the key,
        // but the hasExportPrefix flag is set. Keys are already bare.
        // No additional stripping needed since EnvParser handles it.

        if options.caseInsensitiveKeys {
            key = key.lowercased()
        }

        return key
    }

    /// Normalize value for comparison — strip surrounding whitespace.
    private static func normalizedValue(for entry: EnvEntry) -> String {
        entry.value?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}
