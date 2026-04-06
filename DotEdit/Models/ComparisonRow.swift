import Foundation

/// A single row in the comparison view, representing aligned left/right content.
struct ComparisonRow: Identifiable, Equatable {
    let id = UUID()
    let rowType: RowType
    let leftEntry: EnvEntry?
    let rightEntry: EnvEntry?
    let diffCategory: DiffResult.Category?
    let contextCategory: ContextCategory?

    enum ContextCategory: Equatable {
        case equal, modified, leftOnly, rightOnly
    }

    /// Left line number (from original file).
    var leftLineNumber: Int? { leftEntry?.lineNumber }

    /// Right line number (from original file).
    var rightLineNumber: Int? { rightEntry?.lineNumber }

    /// Whether this row is purely comment/blank content (no key-value data).
    /// Works in both Align mode (rowType .context) and Sequential mode (rowType .diff).
    var isCommentOrBlank: Bool {
        let leftIsNoise = leftEntry.map { $0.type == .comment || $0.type == .blank } ?? true
        let rightIsNoise = rightEntry.map { $0.type == .comment || $0.type == .blank } ?? true
        return leftIsNoise && rightIsNoise
    }

    enum RowType: Equatable {
        /// A key-value pair that was diffed.
        case diff
        /// A context line (comment, blank, malformed) — not diffed.
        case context
    }

    // MARK: - Equatable (exclude id)

    static func == (lhs: ComparisonRow, rhs: ComparisonRow) -> Bool {
        lhs.rowType == rhs.rowType
            && lhs.leftEntry == rhs.leftEntry
            && lhs.rightEntry == rhs.rightEntry
            && lhs.diffCategory == rhs.diffCategory
            && lhs.contextCategory == rhs.contextCategory
    }
}
