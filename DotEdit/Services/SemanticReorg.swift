import Foundation

/// Semantic reorganization of .env entries by prefix groups (DEC-008, DEC-022).
enum SemanticReorg {

    /// How to handle existing comments during reorganization.
    enum CommentHandling: String, CaseIterable {
        case moveWithKey    // Attach comment to its following key (default)
        case moveToEnd      // Collect all comments at the end
        case discard        // Remove all comments

        var label: String {
            switch self {
            case .moveWithKey: "Move with key"
            case .moveToEnd: "Move to end"
            case .discard: "Discard"
            }
        }
    }

    /// Result of a reorganization operation.
    struct ReorgResult {
        let lines: [String]
        let groupCount: Int
        let keyCount: Int
    }

    // MARK: - Public API

    /// Reorganize entries by detecting convention and grouping by prefix.
    /// Returns new raw lines ready to replace the panel's lines array.
    static func reorganize(
        entries: [EnvEntry],
        convention: NamingConvention,
        commentHandling: CommentHandling = .moveWithKey
    ) -> ReorgResult {
        // Separate key-value entries from non-key entries
        let keyEntries = entries.filter { $0.type == .keyValue && $0.key != nil }
        let commentEntries = entries.filter { $0.type == .comment }
        let blankEntries = entries.filter { $0.type == .blank }

        guard !keyEntries.isEmpty else {
            return ReorgResult(lines: entries.map(\.rawLine), groupCount: 0, keyCount: 0)
        }

        // Build comment associations: each comment attaches to the key that follows it
        let commentMap = buildCommentMap(entries: entries, handling: commentHandling)

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

        // Build output lines
        var outputLines: [String] = []
        var groupCount = 0

        for prefix in sortedPrefixes {
            guard let groupEntries = groups[prefix] else { continue }
            let sorted = groupEntries.sorted { ($0.key ?? "") < ($1.key ?? "") }

            // Add blank line separator between groups
            if !outputLines.isEmpty {
                outputLines.append("")
            }

            // Group header (skip when discarding comments)
            if commentHandling != .discard {
                outputLines.append("# === \(prefix.uppercased()) ===")
            }
            groupCount += 1

            // Entries with their associated comments
            for entry in sorted {
                if commentHandling == .moveWithKey, let comments = commentMap[entry.lineNumber] {
                    for comment in comments {
                        outputLines.append(comment)
                    }
                }
                outputLines.append(entry.rawLine)
            }
        }

        // OTHER group for non-conforming keys
        if !otherKeys.isEmpty {
            let sorted = otherKeys.sorted { ($0.key ?? "") < ($1.key ?? "") }

            if !outputLines.isEmpty {
                outputLines.append("")
            }

            if commentHandling != .discard {
                outputLines.append("# === OTHER ===")
            }
            groupCount += 1

            for entry in sorted {
                if commentHandling == .moveWithKey, let comments = commentMap[entry.lineNumber] {
                    for comment in comments {
                        outputLines.append(comment)
                    }
                }
                outputLines.append(entry.rawLine)
            }
        }

        // Handle trailing comments based on mode
        switch commentHandling {
        case .moveWithKey:
            // Orphan comments (no following key) go to end
            let orphanComments = findOrphanComments(entries: entries)
            if !orphanComments.isEmpty {
                outputLines.append("")
                for comment in orphanComments {
                    outputLines.append(comment)
                }
            }

        case .moveToEnd:
            if !commentEntries.isEmpty {
                outputLines.append("")
                outputLines.append("# === COMMENTS ===")
                for entry in commentEntries {
                    outputLines.append(entry.rawLine)
                }
            }

        case .discard:
            break
        }

        return ReorgResult(
            lines: outputLines,
            groupCount: groupCount,
            keyCount: keyEntries.count
        )
    }

    // MARK: - Comment Association

    /// Build a map of lineNumber → [comment rawLines] where comments attach to following keys.
    private static func buildCommentMap(
        entries: [EnvEntry],
        handling: CommentHandling
    ) -> [Int: [String]] {
        guard handling == .moveWithKey else { return [:] }

        var map: [Int: [String]] = [:]
        var pendingComments: [String] = []

        for entry in entries {
            switch entry.type {
            case .comment:
                pendingComments.append(entry.rawLine)

            case .keyValue:
                if !pendingComments.isEmpty {
                    map[entry.lineNumber] = pendingComments
                    pendingComments = []
                }

            case .blank, .malformed:
                // Blank lines break comment association
                if !pendingComments.isEmpty {
                    // These become orphans — will be handled separately
                    pendingComments = []
                }
            }
        }

        return map
    }

    /// Find comments at the end of the file that have no following key.
    private static func findOrphanComments(entries: [EnvEntry]) -> [String] {
        var orphans: [String] = []
        var pendingComments: [String] = []

        for entry in entries {
            switch entry.type {
            case .comment:
                pendingComments.append(entry.rawLine)
            case .keyValue:
                pendingComments = []
            case .blank:
                // Blank line breaks association — pending become orphans
                if !pendingComments.isEmpty {
                    orphans.append(contentsOf: pendingComments)
                    pendingComments = []
                }
            case .malformed:
                pendingComments = []
            }
        }

        // Comments at very end with no following key
        orphans.append(contentsOf: pendingComments)

        return orphans
    }
}
