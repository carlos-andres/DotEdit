import Foundation

/// A row in visual reorg mode — aligns entries across panels by prefix group.
struct AlignedRow: Identifiable, Equatable {
    let id = UUID()
    let leftEntry: EnvEntry?   // nil = gap
    let rightEntry: EnvEntry?  // nil = gap
    let prefixGroup: String    // e.g. "DB", "API", "OTHER", ""
    let diffCategory: DiffResult.Category

    var isLeftGap: Bool { leftEntry == nil }
    var isRightGap: Bool { rightEntry == nil }

    static func == (lhs: AlignedRow, rhs: AlignedRow) -> Bool {
        lhs.leftEntry == rhs.leftEntry
            && lhs.rightEntry == rhs.rightEntry
            && lhs.prefixGroup == rhs.prefixGroup
            && lhs.diffCategory == rhs.diffCategory
    }
}

/// Maps between visual row positions and original entry IDs.
struct DisplayOrderMap {
    let visualToOriginal: [Int: UUID]
    let originalToVisual: [UUID: Int]
    let gapIndices: Set<Int>
    let hiddenEntryIDs: Set<UUID>
}
