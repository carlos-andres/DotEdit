import Foundation

/// Destructive file consolidation: groups, sorts, strips comments.
/// Uses raw lines to preserve exact values, quotes, and export prefixes.
enum ConsolidateEngine {

    struct ConsolidateResult {
        let lines: [String]
        let groupCount: Int
        let keyCount: Int
    }

    /// Consolidate entries: group by prefix, sort alphabetically, strip comments/blanks.
    /// When `includeHeaders` is false, group header comments are omitted for a clean output.
    static func consolidate(entries: [EnvEntry], convention: NamingConvention, includeHeaders: Bool = true) -> ConsolidateResult {
        let keyEntries = entries.filter { $0.type == .keyValue && $0.key != nil }

        guard !keyEntries.isEmpty else {
            return ConsolidateResult(lines: [], groupCount: 0, keyCount: 0)
        }

        // Group keys by prefix
        var groups: [String: [EnvEntry]] = [:]
        var otherKeys: [EnvEntry] = []

        for entry in keyEntries {
            guard let key = entry.key else { continue }
            let entryConvention = NamingConvention.classify(key: key)

            if entryConvention == convention {
                let prefix = NamingConvention.extractPrefix(key: key, convention: convention)
                groups[prefix, default: []].append(entry)
            } else {
                otherKeys.append(entry)
            }
        }

        // Sort prefixes alphabetically
        let sortedPrefixes = groups.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        // Build output
        var outputLines: [String] = []
        var groupCount = 0

        for prefix in sortedPrefixes {
            guard let groupEntries = groups[prefix] else { continue }
            let sorted = groupEntries.sorted { ($0.key ?? "") < ($1.key ?? "") }

            if !outputLines.isEmpty {
                outputLines.append("")
            }

            if includeHeaders {
                outputLines.append("# === \(prefix.uppercased()) ===")
            }
            groupCount += 1

            for entry in sorted {
                outputLines.append(entry.rawLine)
            }
        }

        // OTHER group
        if !otherKeys.isEmpty {
            let sorted = otherKeys.sorted { ($0.key ?? "") < ($1.key ?? "") }

            if !outputLines.isEmpty {
                outputLines.append("")
            }

            if includeHeaders {
                outputLines.append("# === OTHER ===")
            }
            groupCount += 1

            for entry in sorted {
                outputLines.append(entry.rawLine)
            }
        }

        return ConsolidateResult(
            lines: outputLines,
            groupCount: groupCount,
            keyCount: keyEntries.count
        )
    }
}
