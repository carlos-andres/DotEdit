import Foundation

/// Computes gap-aligned rows for visual reorg mode.
/// Groups entries by prefix across both panels, aligning matching keys side-by-side.
enum AlignedReorgEngine {

    // MARK: - Public API

    /// Compute aligned rows from two env files.
    static func computeAlignedRows(
        leftFile: EnvFile,
        rightFile: EnvFile,
        options: DiffEngine.Options = .default
    ) -> [AlignedRow] {
        computeAlignedRowsWithMap(leftFile: leftFile, rightFile: rightFile, options: options).rows
    }

    /// Compute aligned rows with display order map for position tracking.
    static func computeAlignedRowsWithMap(
        leftFile: EnvFile,
        rightFile: EnvFile,
        options: DiffEngine.Options = .default
    ) -> (rows: [AlignedRow], map: DisplayOrderMap) {
        // Step 1: Detect dominant convention per panel independently
        let leftKeys = leftFile.keyValueEntries.compactMap(\.key)
        let rightKeys = rightFile.keyValueEntries.compactMap(\.key)
        let leftConvention = NamingConvention.detectDominant(keys: leftKeys).dominant
        let rightConvention = NamingConvention.detectDominant(keys: rightKeys).dominant

        // Step 2: Build key→entry lookups (first occurrence only)
        let leftLookup = buildKeyLookup(from: leftFile, options: options)
        let rightLookup = buildKeyLookup(from: rightFile, options: options)

        // Step 3: Group keys by prefix using per-panel conventions
        let leftGroups = groupByPrefix(entries: leftLookup, convention: leftConvention)
        let rightGroups = groupByPrefix(entries: rightLookup, convention: rightConvention)

        // Step 4: Merge all prefix groups from both sides, sorted alphabetically
        let allPrefixes = Set(leftGroups.keys).union(rightGroups.keys)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        // Step 5: Build aligned rows
        var rows: [AlignedRow] = []
        var visualToOriginal: [Int: UUID] = [:]
        var originalToVisual: [UUID: Int] = [:]
        var gapIndices: Set<Int> = []

        for prefix in allPrefixes {
            let leftEntries = leftGroups[prefix] ?? []
            let rightEntries = rightGroups[prefix] ?? []

            // Collect all unique keys from both sides, sorted alphabetically
            let leftKeyEntries = buildNormalizedKeyMap(entries: leftEntries, options: options)
            let rightKeyEntries = buildNormalizedKeyMap(entries: rightEntries, options: options)

            let allKeys = mergeAndSortKeys(
                leftKeys: Array(leftKeyEntries.keys),
                rightKeys: Array(rightKeyEntries.keys)
            )

            for normKey in allKeys {
                let leftEntry = leftKeyEntries[normKey]
                let rightEntry = rightKeyEntries[normKey]
                let category = categorize(left: leftEntry, right: rightEntry, options: options)

                let rowIndex = rows.count
                let row = AlignedRow(
                    leftEntry: leftEntry,
                    rightEntry: rightEntry,
                    prefixGroup: prefix,
                    diffCategory: category
                )
                rows.append(row)

                // Track mappings
                if let entry = leftEntry {
                    visualToOriginal[rowIndex] = entry.id
                    originalToVisual[entry.id] = rowIndex
                } else {
                    gapIndices.insert(rowIndex)
                }
                if let entry = rightEntry {
                    if visualToOriginal[rowIndex] == nil {
                        visualToOriginal[rowIndex] = entry.id
                    }
                    originalToVisual[entry.id] = rowIndex
                }
            }
        }

        // Step 6: Add malformed entries to "OTHER" group at bottom (Q-006 / DEC-038)
        let leftMalformed = leftFile.entries.filter { $0.type == .malformed }
        let rightMalformed = rightFile.entries.filter { $0.type == .malformed }
        if !leftMalformed.isEmpty || !rightMalformed.isEmpty {
            for entry in leftMalformed {
                let rowIndex = rows.count
                rows.append(AlignedRow(
                    leftEntry: entry, rightEntry: nil,
                    prefixGroup: "OTHER", diffCategory: .leftOnly
                ))
                visualToOriginal[rowIndex] = entry.id
                originalToVisual[entry.id] = rowIndex
            }
            for entry in rightMalformed {
                let rowIndex = rows.count
                rows.append(AlignedRow(
                    leftEntry: nil, rightEntry: entry,
                    prefixGroup: "OTHER", diffCategory: .rightOnly
                ))
                visualToOriginal[rowIndex] = entry.id
                originalToVisual[entry.id] = rowIndex
            }
        }

        // Step 7: Collect hidden entry IDs (comments + blanks from both files)
        var hiddenEntryIDs: Set<UUID> = []
        for entry in leftFile.entries where entry.type == .comment || entry.type == .blank {
            hiddenEntryIDs.insert(entry.id)
        }
        for entry in rightFile.entries where entry.type == .comment || entry.type == .blank {
            hiddenEntryIDs.insert(entry.id)
        }

        let map = DisplayOrderMap(
            visualToOriginal: visualToOriginal,
            originalToVisual: originalToVisual,
            gapIndices: gapIndices,
            hiddenEntryIDs: hiddenEntryIDs
        )

        return (rows, map)
    }

    // MARK: - Private Helpers

    /// Build key→entry lookup from file, using first occurrence only.
    private static func buildKeyLookup(
        from file: EnvFile,
        options: DiffEngine.Options
    ) -> [String: EnvEntry] {
        var lookup: [String: EnvEntry] = [:]
        for entry in file.keyValueEntries {
            guard let key = entry.key else { continue }
            let normKey = options.caseInsensitiveKeys ? key.lowercased() : key
            if lookup[normKey] == nil {
                lookup[normKey] = entry
            }
        }
        return lookup
    }

    /// Group entries by prefix using given convention.
    /// Non-conforming entries go to "OTHER".
    private static func groupByPrefix(
        entries: [String: EnvEntry],
        convention: NamingConvention
    ) -> [String: [EnvEntry]] {
        var groups: [String: [EnvEntry]] = [:]
        for (_, entry) in entries {
            guard let key = entry.key else { continue }
            let entryConvention = NamingConvention.classify(key: key)
            let prefix: String
            if entryConvention == convention {
                prefix = NamingConvention.extractPrefix(key: key, convention: convention)
                    .uppercased()
            } else {
                prefix = "OTHER"
            }
            groups[prefix, default: []].append(entry)
        }
        return groups
    }

    /// Build normalized key → entry map for merging.
    private static func buildNormalizedKeyMap(
        entries: [EnvEntry],
        options: DiffEngine.Options
    ) -> [String: EnvEntry] {
        var map: [String: EnvEntry] = [:]
        for entry in entries {
            guard let key = entry.key else { continue }
            let normKey = options.caseInsensitiveKeys ? key.lowercased() : key
            if map[normKey] == nil {
                map[normKey] = entry
            }
        }
        return map
    }

    /// Merge keys from both sides and sort alphabetically, deduplicating.
    private static func mergeAndSortKeys(leftKeys: [String], rightKeys: [String]) -> [String] {
        var seen: Set<String> = []
        var allKeys: [String] = []
        for key in leftKeys + rightKeys {
            if !seen.contains(key) {
                seen.insert(key)
                allKeys.append(key)
            }
        }
        return allKeys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Categorize the diff between left and right entries.
    private static func categorize(
        left: EnvEntry?,
        right: EnvEntry?,
        options: DiffEngine.Options
    ) -> DiffResult.Category {
        switch (left, right) {
        case (.some(let l), .some(let r)):
            let leftVal = l.value?.trimmingCharacters(in: .whitespaces) ?? ""
            let rightVal = r.value?.trimmingCharacters(in: .whitespaces) ?? ""
            return leftVal == rightVal ? .equal : .modified
        case (.some, .none):
            return .leftOnly
        case (.none, .some):
            return .rightOnly
        case (.none, .none):
            return .equal // shouldn't happen
        }
    }
}
