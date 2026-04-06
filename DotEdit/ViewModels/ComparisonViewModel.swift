import SwiftUI

/// Drives the comparison view: merges diff results with context lines,
/// tracks scroll state, divider position, editing state, and diff statistics.
@MainActor
@Observable
final class ComparisonViewModel {
    // MARK: - Original Inputs

    let originalLeftFile: EnvFile
    let originalRightFile: EnvFile

    /// Security-scoped URLs from NSOpenPanel for sandbox access during save (DEC-055).
    var leftSourceURL: URL?
    var rightSourceURL: URL?

    // MARK: - Mutable Editing State

    /// Raw lines for each panel — source of truth for editing.
    var leftLines: [String]
    var rightLines: [String]

    /// Current parsed files (re-parsed on edit).
    private(set) var leftFile: EnvFile
    private(set) var rightFile: EnvFile

    /// Dirty tracking.
    private(set) var isLeftDirty: Bool = false
    private(set) var isRightDirty: Bool = false

    // MARK: - Undo

    let leftUndoManager: UndoManager
    let rightUndoManager: UndoManager

    // MARK: - Computed State

    private(set) var rows: [ComparisonRow] = []
    private(set) var diffStats: DiffStats = .empty

    // MARK: - UI State

    /// Fraction of width allocated to left panel (0.2–0.8).
    var leftFraction: CGFloat = 0.5

    /// Computed panel widths for a given container size.
    struct PanelLayout {
        let leftWidth: CGFloat
        let rightWidth: CGFloat
    }

    /// Compute panel layout widths for a given container size.
    func panelLayout(for size: CGSize) -> PanelLayout {
        let totalReserved = Theme.gutterWidth + Theme.scrollBarReservedWidth
        let leftWidth = (size.width - totalReserved) * leftFraction
        let rightWidth = (size.width - totalReserved) * (1 - leftFraction)
        return PanelLayout(leftWidth: leftWidth, rightWidth: rightWidth)
    }

    /// Currently scrolled-to row ID.
    var scrollTarget: ComparisonRow.ID?

    /// Whether files are identical (no diffs at all).
    var filesAreIdentical: Bool { diffStats.modified == 0 && diffStats.leftOnly == 0 && diffStats.rightOnly == 0 }

    /// Whether equal rows are collapsed (visual-only, no data modification).
    var isCollapsed: Bool = false { didSet { updateVisibleRows() } }

    /// Whether comment/blank rows are hidden (visual-only, no data modification).
    var areCommentsHidden: Bool = false { didSet { updateVisibleRows() } }

    /// Rows visible in the UI — filters out hidden comments and/or equal rows when collapsed.
    private(set) var visibleRows: [ComparisonRow] = []

    /// Recomputes `visibleRows` from current `rows`, `areCommentsHidden`, and `isCollapsed`.
    private func updateVisibleRows() {
        var result = rows
        if areCommentsHidden {
            result = result.filter { !$0.isCommentOrBlank }
        }
        if isCollapsed {
            result = result.filter { row in
                if row.rowType == .context { return row.contextCategory != .equal }
                return row.diffCategory != .equal
            }
        }
        visibleRows = result
    }

    /// Number of rows hidden by collapse.
    var collapsedCount: Int {
        guard isCollapsed else { return 0 }
        return rows.count - visibleRows.count
    }

    // MARK: - Visual Reorg State

    /// Whether visual reorg (prefix-grouped display) is active.
    var isVisualReorgActive: Bool = false {
        didSet {
            if isVisualReorgActive { clearReorgPreview() }
            computeAlignedReorg()
        }
    }

    // MARK: - Reorg Preview State

    /// Whether visual reorg preview (sorted display) is active — display only, no file modification.
    var isReorgPreviewActive: Bool = false

    /// Comment handling for current preview.
    private(set) var previewCommentHandling: SemanticReorg.CommentHandling = .moveWithKey

    /// Rows sorted by prefix group for preview display.
    var previewRows: [ComparisonRow] {
        guard isReorgPreviewActive else { return [] }
        let hideFromPreview = previewCommentHandling == .discard || areCommentsHidden
        return sortRowsByPrefixGroup(rows, hideComments: hideFromPreview)
    }

    /// Activate reorg preview: sorted display only, no file modification.
    func activateReorgPreview(hideComments: Bool) {
        // Clear mutually exclusive modes
        if isVisualReorgActive { isVisualReorgActive = false }
        if settings?.sequentialDiff ?? false {
            settings?.sequentialDiff = false
            reDiff()
        }
        previewCommentHandling = hideComments ? .discard : .moveWithKey
        isReorgPreviewActive = true
    }

    /// Clear reorg preview, return to original display order.
    func clearReorgPreview() {
        isReorgPreviewActive = false
    }

    /// Sort ComparisonRows by prefix group for preview display.
    private func sortRowsByPrefixGroup(_ sourceRows: [ComparisonRow], hideComments: Bool) -> [ComparisonRow] {
        // Detect conventions for both sides
        let leftConvention = detectConvention(side: .left).dominant
        let rightConvention = detectConvention(side: .right).dominant

        // Extract prefix for a row: prefer left entry key, fall back to right
        func prefixFor(_ row: ComparisonRow) -> String {
            if let key = row.leftEntry?.key {
                return NamingConvention.extractPrefix(key: key, convention: leftConvention).uppercased()
            }
            if let key = row.rightEntry?.key {
                return NamingConvention.extractPrefix(key: key, convention: rightConvention).uppercased()
            }
            return "~OTHER"
        }

        func sortKeyFor(_ row: ComparisonRow) -> String {
            (row.leftEntry?.key ?? row.rightEntry?.key ?? "").lowercased()
        }

        // Separate key-value rows from context rows
        var kvRows: [ComparisonRow] = []
        var contextRows: [ComparisonRow] = []

        for row in sourceRows {
            if row.rowType == .diff {
                kvRows.append(row)
            } else {
                contextRows.append(row)
            }
        }

        // Sort key-value rows by prefix group, then by key
        let sorted = kvRows.sorted { a, b in
            let prefixA = prefixFor(a)
            let prefixB = prefixFor(b)
            if prefixA != prefixB {
                return prefixA.localizedCaseInsensitiveCompare(prefixB) == .orderedAscending
            }
            return sortKeyFor(a).localizedCaseInsensitiveCompare(sortKeyFor(b)) == .orderedAscending
        }

        if hideComments {
            return sorted
        }

        // Append context rows at the end
        return sorted + contextRows
    }

    /// Aligned rows for visual reorg mode.
    private(set) var alignedRows: [AlignedRow] = []

    /// Display order map for position tracking in visual reorg.
    private(set) var displayOrderMap: DisplayOrderMap?

    /// Aligned rows visible in the UI — filters out equal rows when collapsed.
    var visibleAlignedRows: [AlignedRow] {
        guard isCollapsed else { return alignedRows }
        return alignedRows.filter { $0.diffCategory != .equal }
    }

    /// Number of aligned rows hidden by collapse.
    var collapsedAlignedCount: Int {
        guard isCollapsed else { return 0 }
        return alignedRows.count - visibleAlignedRows.count
    }

    // MARK: - Search State

    /// Search state and logic — delegated to SearchState.
    let search = SearchState()

    // MARK: - Warning Aggregation

    /// All warnings from both files.
    var allWarnings: [EnvFile.FileWarning] {
        var warnings: [EnvFile.FileWarning] = []
        warnings.append(contentsOf: leftFile.allWarnings)
        warnings.append(contentsOf: rightFile.allWarnings)
        return warnings
    }

    /// Warning count for display.
    var warningCount: Int { allWarnings.count }

    // MARK: - Accessibility State (BL-010)

    /// Whether the left file is currently accessible on disk.
    var isLeftAccessible: Bool = true

    /// Whether the right file is currently accessible on disk.
    var isRightAccessible: Bool = true

    /// Update accessibility state for a URL.
    func setAccessibility(url: URL, isAccessible: Bool) {
        let resolved = url.resolvingSymlinksInPath().path
        if resolved == leftFile.filePath || URL(fileURLWithPath: leftFile.filePath).resolvingSymlinksInPath().path == resolved {
            isLeftAccessible = isAccessible
        }
        if resolved == rightFile.filePath || URL(fileURLWithPath: rightFile.filePath).resolvingSymlinksInPath().path == resolved {
            isRightAccessible = isAccessible
        }
    }

    // MARK: - Settings

    /// App settings for diff options and save behavior.
    var settings: AppSettings?

    // MARK: - Debounce

    private var reDiffTask: Task<Void, Never>?
    private let debounceInterval: UInt64 = 150_000_000 // 0.15s in nanoseconds

    // MARK: - Init

    init(leftFile: EnvFile, rightFile: EnvFile, settings: AppSettings? = nil) {
        self.settings = settings
        self.originalLeftFile = leftFile
        self.originalRightFile = rightFile
        self.leftFile = leftFile
        self.rightFile = rightFile
        self.leftLines = leftFile.entries.map(\.rawLine)
        self.rightLines = rightFile.entries.map(\.rawLine)
        self.leftUndoManager = UndoManager()
        self.leftUndoManager.levelsOfUndo = 100
        self.rightUndoManager = UndoManager()
        self.rightUndoManager.levelsOfUndo = 100
        computeRows()
        search.onSearchChanged = { [weak self] in self?.performSearch() }
    }

    /// Perform search and auto-uncollapse if results found.
    func performSearch() {
        if isVisualReorgActive {
            search.performSearch(alignedRows: alignedRows)
        } else if isReorgPreviewActive {
            search.performSearch(rows: previewRows)
        } else {
            search.performSearch(rows: visibleRows)
        }
        if !search.searchMatches.isEmpty && isCollapsed {
            isCollapsed = false
        }
    }

    /// Move to next search match and scroll.
    func nextMatch() {
        search.nextMatch()
        scrollToCurrentMatch()
    }

    /// Move to previous search match and scroll.
    func previousMatch() {
        search.previousMatch()
        scrollToCurrentMatch()
    }

    /// Clear search state.
    func clearSearch() {
        search.clear()
    }

    /// Scroll to the current search match.
    private func scrollToCurrentMatch() {
        guard let match = search.currentMatch else { return }
        if isVisualReorgActive {
            guard match.rowIndex < alignedRows.count else { return }
            scrollTarget = alignedRows[match.rowIndex].id
        } else if isReorgPreviewActive {
            let preview = previewRows
            guard match.rowIndex < preview.count else { return }
            scrollTarget = preview[match.rowIndex].id
        } else {
            guard match.rowIndex < rows.count else { return }
            scrollTarget = rows[match.rowIndex].id
        }
    }

    // MARK: - Editing API

    /// Update a line on the given panel and schedule re-diff.
    func updateLine(at index: Int, to newValue: String, side: PanelSide) {
        guard index >= 0, index < lines(for: side).count else { return }
        let oldValue = lines(for: side)[index]
        guard oldValue != newValue else { return }

        undoManager(for: side).registerUndo(withTarget: self) { vm in
            vm.updateLine(at: index, to: oldValue, side: side)
        }

        setLine(at: index, to: newValue, side: side)
        setDirty(true, side: side)
        scheduleReDiff()
    }

    // MARK: - Computed State (Dirty)

    /// Whether either panel has unsaved changes.
    var hasUnsavedChanges: Bool { isLeftDirty || isRightDirty }

    // MARK: - Save API

    /// Save all dirty panels to disk. Returns first warning if any (DEC-055).
    @discardableResult
    func saveAll() throws -> String? {
        var warning: String?
        if isLeftDirty { warning = try save(side: .left) }
        if isRightDirty {
            let rightWarning = try save(side: .right)
            warning = warning ?? rightWarning
        }
        return warning
    }

    /// Save a panel's content to disk, clear dirty state and undo stack (DEC-023).
    /// Returns optional warning from backup (DEC-055).
    @discardableResult
    func save(side: PanelSide) throws -> String? {
        let content = lines(for: side).joined(separator: "\n")
        let url = URL(fileURLWithPath: file(for: side).filePath)
        let backup = settings?.createBackupOnSave ?? true
        let sourceURL = side == .left ? leftSourceURL : rightSourceURL
        let warning = try FileSaver.save(
            content: content,
            to: url,
            createBackup: backup,
            securityScopedURL: sourceURL
        )
        setDirty(false, side: side)
        undoManager(for: side).removeAllActions()
        return warning
    }

    /// Save a panel's content to a new URL, update internal path, clear dirty state (BL-009).
    func saveSideAs(side: PanelSide, to newURL: URL) throws {
        let content = lines(for: side).joined(separator: "\n")
        try FileSaver.save(content: content, to: newURL, createBackup: false)
        let parsed = EnvParser.parse(content: content, filePath: newURL.path)
        setFile(parsed, side: side)
        setLines(parsed.entries.map(\.rawLine), side: side)
        setDirty(false, side: side)
        undoManager(for: side).removeAllActions()
        computeRows()
    }

    // MARK: - Reload API

    /// Reload both files from disk, reset dirty state and undo stacks, recompute rows.
    func reload(leftURL: URL, rightURL: URL) throws {
        let newLeft = try FileLoader.load(url: leftURL)
        let newRight = try FileLoader.load(url: rightURL)

        leftFile = newLeft
        rightFile = newRight
        leftLines = newLeft.entries.map(\.rawLine)
        rightLines = newRight.entries.map(\.rawLine)

        isLeftDirty = false
        isRightDirty = false
        leftUndoManager.removeAllActions()
        rightUndoManager.removeAllActions()

        computeRows()
    }

    /// Reload a single side from disk.
    func reloadSide(url: URL, side: PanelSide) throws {
        let newFile = try FileLoader.load(url: url)
        setFile(newFile, side: side)
        setLines(newFile.entries.map(\.rawLine), side: side)
        setDirty(false, side: side)
        undoManager(for: side).removeAllActions()
        computeRows()
    }

    // MARK: - Convention Detection API

    /// Detect the dominant naming convention for a panel's keys.
    func detectConvention(side: PanelSide) -> NamingConvention.DetectionResult {
        let file = side == .left ? leftFile : rightFile
        let keys = file.entries.compactMap { $0.type == .keyValue ? $0.key : nil }
        return NamingConvention.detectDominant(keys: keys)
    }

    /// Check if a panel has duplicate keys.
    func hasDuplicateKeys(side: PanelSide) -> Bool {
        let file = side == .left ? leftFile : rightFile
        let keys = file.entries.compactMap { $0.type == .keyValue ? $0.key : nil }
        return Set(keys).count < keys.count
    }

    // MARK: - Consolidate API

    /// Consolidate a panel: group, sort, strip comments. Registered as single undo step.
    /// When `includeHeaders` is false, group header comments are omitted.
    func consolidate(side: PanelSide, convention: NamingConvention, includeHeaders: Bool = true) -> ConsolidateEngine.ConsolidateResult {
        let oldLines = lines(for: side)
        let result = ConsolidateEngine.consolidate(entries: file(for: side).entries, convention: convention, includeHeaders: includeHeaders)

        undoManager(for: side).registerUndo(withTarget: self) { vm in
            vm.setLines(oldLines, side: side)
            vm.setDirty(true, side: side)
            vm.reDiff()
        }

        setLines(result.lines, side: side)
        setDirty(true, side: side)
        reDiff()
        return result
    }

    // MARK: - Reorganize API

    /// Reorganize a panel: group keys by prefix, respecting comment handling setting.
    /// Registered as a single undo step.
    func reorganize(side: PanelSide, convention: NamingConvention, commentHandling: SemanticReorg.CommentHandling) -> SemanticReorg.ReorgResult {
        let oldLines = lines(for: side)
        let result = SemanticReorg.reorganize(entries: file(for: side).entries, convention: convention, commentHandling: commentHandling)

        undoManager(for: side).registerUndo(withTarget: self) { vm in
            vm.setLines(oldLines, side: side)
            vm.setDirty(true, side: side)
            vm.reDiff()
        }

        setLines(result.lines, side: side)
        setDirty(true, side: side)
        reDiff()
        return result
    }

    // MARK: - Dedup API

    /// Result of a deduplication operation.
    struct DedupResult {
        let removedCount: Int
        let removedKeys: [String]
    }

    /// Remove duplicate keys from a panel, keeping first occurrence.
    /// Registered as a single undo step.
    func dedup(side: PanelSide) -> DedupResult {
        let sideFile = file(for: side)
        let sideLines = lines(for: side)

        // Find indices of duplicate entries (keep first, remove subsequent)
        var seenKeys: Set<String> = []
        var indicesToRemove: [Int] = []
        var removedKeys: [String] = []

        for entry in sideFile.entries {
            guard entry.type == .keyValue, let key = entry.key else { continue }
            if seenKeys.contains(key) {
                indicesToRemove.append(entry.lineNumber - 1)
                if !removedKeys.contains(key) {
                    removedKeys.append(key)
                }
            } else {
                seenKeys.insert(key)
            }
        }

        guard !indicesToRemove.isEmpty else {
            return DedupResult(removedCount: 0, removedKeys: [])
        }

        // Build new lines array with duplicates removed
        let indicesToRemoveSet = Set(indicesToRemove)
        let newLines = sideLines.enumerated().compactMap { idx, line in
            indicesToRemoveSet.contains(idx) ? nil : line
        }

        let oldLines = sideLines
        undoManager(for: side).registerUndo(withTarget: self) { vm in
            vm.setLines(oldLines, side: side)
            vm.setDirty(true, side: side)
            vm.reDiff()
        }

        setLines(newLines, side: side)
        setDirty(true, side: side)
        reDiff()
        return DedupResult(removedCount: indicesToRemove.count, removedKeys: removedKeys)
    }

    // MARK: - Remove Comments API

    /// Result of a comment removal operation.
    struct RemoveCommentsResult {
        let removedCount: Int
    }

    /// Remove all comment and blank lines from a panel.
    /// Registered as a single undo step.
    func removeComments(side: PanelSide) -> RemoveCommentsResult {
        let sideFile = file(for: side)
        let sideLines = lines(for: side)

        // Find indices of comment/blank entries
        var indicesToRemove: [Int] = []
        for entry in sideFile.entries {
            if entry.type == .comment || entry.type == .blank {
                indicesToRemove.append(entry.lineNumber - 1)
            }
        }

        guard !indicesToRemove.isEmpty else {
            return RemoveCommentsResult(removedCount: 0)
        }

        // Build new lines array with comments/blanks removed
        let indicesToRemoveSet = Set(indicesToRemove)
        let newLines = sideLines.enumerated().compactMap { idx, line in
            indicesToRemoveSet.contains(idx) ? nil : line
        }

        let oldLines = sideLines
        undoManager(for: side).registerUndo(withTarget: self) { vm in
            vm.setLines(oldLines, side: side)
            vm.setDirty(true, side: side)
            vm.reDiff()
        }

        setLines(newLines, side: side)
        setDirty(true, side: side)
        reDiff()
        return RemoveCommentsResult(removedCount: indicesToRemove.count)
    }

    // MARK: - Transfer API

    /// Transfer a row's source entry to the target panel (normal diff mode).
    /// Modified: replace target line with source's rawLine.
    /// LeftOnly/RightOnly: append source's rawLine to target.
    func transfer(row: ComparisonRow, to target: PanelSide) {
        guard let cat = row.diffCategory, row.rowType == .diff else { return }
        let source: PanelSide = target == .left ? .right : .left
        let sourceOnlyCategory: DiffResult.Category = source == .left ? .leftOnly : .rightOnly

        switch cat {
        case .modified:
            guard let sourceEntry = entry(for: source, in: row),
                  let targetEntry = entry(for: target, in: row) else { return }
            transferModified(sourceEntry: sourceEntry, targetEntry: targetEntry, to: target)

        case sourceOnlyCategory:
            guard let sourceEntry = entry(for: source, in: row) else { return }
            transferOnlyAppend(sourceEntry: sourceEntry, to: target)

        default:
            break
        }
    }

    /// Transfer a row's source entry to the target panel (visual reorg mode).
    /// Modified: replace target line. LeftOnly/RightOnly: insert at smart position.
    func transferAligned(row: AlignedRow, to target: PanelSide) {
        let source: PanelSide = target == .left ? .right : .left
        let sourceOnlyCategory: DiffResult.Category = source == .left ? .leftOnly : .rightOnly

        switch row.diffCategory {
        case .modified:
            guard let sourceEntry = entry(for: source, inAligned: row),
                  let targetEntry = entry(for: target, inAligned: row) else { return }
            transferModified(sourceEntry: sourceEntry, targetEntry: targetEntry, to: target)

        case sourceOnlyCategory:
            guard let sourceEntry = entry(for: source, inAligned: row) else { return }
            transferOnlyInsert(sourceEntry: sourceEntry, to: target, prefixGroup: row.prefixGroup)

        default:
            break
        }
    }

    // MARK: - Transfer Internals

    /// Replace a modified entry's line on the target side.
    private func transferModified(sourceEntry: EnvEntry, targetEntry: EnvEntry, to target: PanelSide) {
        let targetIdx = targetEntry.lineNumber - 1
        guard targetIdx >= 0, targetIdx < lines(for: target).count else { return }
        let oldValue = lines(for: target)[targetIdx]
        let newValue = transferValue(sourceEntry: sourceEntry, targetEntry: targetEntry)

        undoManager(for: target).registerUndo(withTarget: self) { vm in
            vm.setLine(at: targetIdx, to: oldValue, side: target)
            vm.setDirty(true, side: target)
            vm.scheduleReDiff()
        }

        setLine(at: targetIdx, to: newValue, side: target)
        setDirty(true, side: target)
        scheduleReDiff()
    }

    /// Transfer a source-only entry to target by appending (normal diff mode).
    private func transferOnlyAppend(sourceEntry: EnvEntry, to target: PanelSide) {
        let isCaseInsensitive = settings?.caseInsensitiveKeys ?? false

        // DEC-043: Key-aware transfer — check if key exists on target side
        if let key = sourceEntry.key,
           let existing = findExistingKeyIndex(key: key, in: file(for: target), caseInsensitive: isCaseInsensitive) {
            let oldValue = lines(for: target)[existing.lineIndex]
            let targetEntry = file(for: target).entries[existing.entryIndex]
            let newValue = transferValue(sourceEntry: sourceEntry, targetEntry: targetEntry)

            undoManager(for: target).registerUndo(withTarget: self) { vm in
                vm.setLine(at: existing.lineIndex, to: oldValue, side: target)
                vm.setDirty(true, side: target)
                vm.scheduleReDiff()
            }

            setLine(at: existing.lineIndex, to: newValue, side: target)
        } else {
            let newLine = sourceEntry.rawLine
            let insertIdx = lines(for: target).count

            undoManager(for: target).registerUndo(withTarget: self) { vm in
                if insertIdx < vm.lines(for: target).count {
                    vm.removeLine(at: insertIdx, side: target)
                }
                vm.setDirty(true, side: target)
                vm.scheduleReDiff()
            }

            appendLine(newLine, side: target)
        }
        setDirty(true, side: target)
        scheduleReDiff()
    }

    /// Transfer a source-only entry to target by smart-inserting (visual reorg mode).
    private func transferOnlyInsert(sourceEntry: EnvEntry, to target: PanelSide, prefixGroup: String) {
        let isCaseInsensitive = settings?.caseInsensitiveKeys ?? false

        // DEC-043: Key-aware transfer — check if key exists on target side
        if let key = sourceEntry.key,
           let existing = findExistingKeyIndex(key: key, in: file(for: target), caseInsensitive: isCaseInsensitive) {
            let oldValue = lines(for: target)[existing.lineIndex]
            let targetEntry = file(for: target).entries[existing.entryIndex]
            let newValue = transferValue(sourceEntry: sourceEntry, targetEntry: targetEntry)

            undoManager(for: target).registerUndo(withTarget: self) { vm in
                vm.setLine(at: existing.lineIndex, to: oldValue, side: target)
                vm.setDirty(true, side: target)
                vm.scheduleReDiff()
            }

            setLine(at: existing.lineIndex, to: newValue, side: target)
        } else {
            let insertIdx = findInsertPosition(for: sourceEntry, in: file(for: target), prefixGroup: prefixGroup)
            let newLine = sourceEntry.rawLine

            undoManager(for: target).registerUndo(withTarget: self) { vm in
                if insertIdx < vm.lines(for: target).count {
                    vm.removeLine(at: insertIdx, side: target)
                }
                vm.setDirty(true, side: target)
                vm.scheduleReDiff()
            }

            insertLine(newLine, at: insertIdx, side: target)
        }
        setDirty(true, side: target)
        scheduleReDiff()
    }

    // MARK: - Panel Accessors

    /// Get lines array for a side.
    func lines(for side: PanelSide) -> [String] {
        side == .left ? leftLines : rightLines
    }

    /// Get file for a side.
    private func file(for side: PanelSide) -> EnvFile {
        side == .left ? leftFile : rightFile
    }

    /// Set file for a side.
    private func setFile(_ newFile: EnvFile, side: PanelSide) {
        switch side {
        case .left: leftFile = newFile
        case .right: rightFile = newFile
        }
    }

    /// Get undo manager for a side.
    private func undoManager(for side: PanelSide) -> UndoManager {
        side == .left ? leftUndoManager : rightUndoManager
    }

    /// Set a line at index for a side.
    private func setLine(at index: Int, to value: String, side: PanelSide) {
        switch side {
        case .left: leftLines[index] = value
        case .right: rightLines[index] = value
        }
    }

    /// Remove a line at index for a side.
    private func removeLine(at index: Int, side: PanelSide) {
        switch side {
        case .left: leftLines.remove(at: index)
        case .right: rightLines.remove(at: index)
        }
    }

    /// Append a line for a side.
    private func appendLine(_ line: String, side: PanelSide) {
        switch side {
        case .left: leftLines.append(line)
        case .right: rightLines.append(line)
        }
    }

    /// Insert a line at index for a side.
    private func insertLine(_ line: String, at index: Int, side: PanelSide) {
        switch side {
        case .left: leftLines.insert(line, at: index)
        case .right: rightLines.insert(line, at: index)
        }
    }

    /// Set all lines for a side.
    private func setLines(_ newLines: [String], side: PanelSide) {
        switch side {
        case .left: leftLines = newLines
        case .right: rightLines = newLines
        }
    }

    /// Set dirty flag for a side.
    private func setDirty(_ dirty: Bool, side: PanelSide) {
        switch side {
        case .left: isLeftDirty = dirty
        case .right: isRightDirty = dirty
        }
    }

    /// Get entry for a side from a ComparisonRow.
    private func entry(for side: PanelSide, in row: ComparisonRow) -> EnvEntry? {
        side == .left ? row.leftEntry : row.rightEntry
    }

    /// Get entry for a side from an AlignedRow.
    private func entry(for side: PanelSide, inAligned row: AlignedRow) -> EnvEntry? {
        side == .left ? row.leftEntry : row.rightEntry
    }

    /// Find insert position near prefix group neighbors in target file.
    private func findInsertPosition(for entry: EnvEntry, in targetFile: EnvFile, prefixGroup: String) -> Int {
        let targetKeys = targetFile.keyValueEntries.compactMap(\.key)
        let convention = NamingConvention.detectDominant(keys: targetKeys).dominant

        // Find last entry in target file with same prefix group
        var lastGroupIdx: Int?
        for targetEntry in targetFile.entries {
            guard targetEntry.type == .keyValue, let key = targetEntry.key else { continue }
            let prefix = NamingConvention.extractPrefix(key: key, convention: convention).uppercased()
            if prefix == prefixGroup {
                lastGroupIdx = targetEntry.lineNumber - 1
            }
        }

        // Insert after last group member, or append to end
        if let idx = lastGroupIdx {
            return min(idx + 1, targetFile.entries.count)
        }
        return targetFile.entries.count
    }

    /// Find index of an existing key in target file's entries.
    /// Returns the lineNumber-based index in the lines array, or nil if key not found. (DEC-043)
    private func findExistingKeyIndex(key: String, in targetFile: EnvFile, caseInsensitive: Bool = false) -> (entryIndex: Int, lineIndex: Int)? {
        for (i, entry) in targetFile.entries.enumerated() {
            guard entry.type == .keyValue, let entryKey = entry.key else { continue }
            let matches = caseInsensitive
                ? entryKey.lowercased() == key.lowercased()
                : entryKey == key
            if matches {
                return (i, entry.lineNumber - 1)
            }
        }
        return nil
    }

    /// Compute transfer value respecting transfer mode setting.
    /// For value-only mode on modified keys: keeps target's key structure, replaces only the value.
    private func transferValue(sourceEntry: EnvEntry, targetEntry: EnvEntry) -> String {
        guard settings?.transferMode == .valueOnly else {
            return sourceEntry.rawLine
        }
        return reconstructLine(targetEntry: targetEntry, sourceValue: sourceEntry.value ?? "")
    }

    /// Rebuild a line keeping target's export prefix, key, and quote style — replacing only the value.
    private func reconstructLine(targetEntry: EnvEntry, sourceValue: String) -> String {
        guard let key = targetEntry.key else { return sourceValue }

        var line = ""
        if targetEntry.hasExportPrefix { line += "export " }
        line += key
        line += "="

        switch targetEntry.quoteStyle {
        case .none: line += sourceValue
        case .single: line += "'\(sourceValue)'"
        case .double: line += "\"\(sourceValue)\""
        case .backtick: line += "`\(sourceValue)`"
        }

        return line
    }

    // MARK: - External Change Summary (BL-004)

    /// Summary of external changes for the diff sheet.
    struct ExternalChangeSummary {
        let stats: DiffStats
        let changes: [DiffResult]
        let sideLabel: String
    }

    /// Compute a diff summary between the current in-memory file and what's on disk.
    /// Returns stats + non-equal results (capped at 50).
    func computeExternalChangeSummary(for url: URL, side: PanelSide) throws -> ExternalChangeSummary {
        let newFile = try FileLoader.load(url: url)
        let currentFile = side == .left ? leftFile : rightFile
        let sideLabel = side == .left ? "Left" : "Right"

        let options = settings?.diffOptions ?? .default
        let diffResults = DiffEngine.diff(left: currentFile, right: newFile, options: options)

        var equal = 0, modified = 0, leftOnly = 0, rightOnly = 0
        var nonEqual: [DiffResult] = []

        for r in diffResults {
            switch r.category {
            case .equal: equal += 1
            case .modified:
                modified += 1
                if nonEqual.count < 50 { nonEqual.append(r) }
            case .leftOnly:
                leftOnly += 1
                if nonEqual.count < 50 { nonEqual.append(r) }
            case .rightOnly:
                rightOnly += 1
                if nonEqual.count < 50 { nonEqual.append(r) }
            }
        }

        let stats = DiffStats(equal: equal, modified: modified, leftOnly: leftOnly, rightOnly: rightOnly)
        return ExternalChangeSummary(stats: stats, changes: nonEqual, sideLabel: sideLabel)
    }

    /// Re-parse both files from current lines and recompute diff.
    func reDiff() {
        let leftContent = leftLines.joined(separator: "\n")
        let rightContent = rightLines.joined(separator: "\n")

        leftFile = EnvParser.parse(content: leftContent, filePath: originalLeftFile.filePath)
        rightFile = EnvParser.parse(content: rightContent, filePath: originalRightFile.filePath)

        // Update lines arrays to match re-parsed entries (handles multiline joining etc.)
        let newLeft = leftFile.entries.map(\.rawLine)
        let newRight = rightFile.entries.map(\.rawLine)
        if newLeft != leftLines { leftLines = newLeft }
        if newRight != rightLines { rightLines = newRight }

        computeRows()

        if isVisualReorgActive {
            computeAlignedReorg()
        }
    }

    // MARK: - Visual Reorg Computation

    /// Compute aligned rows from current files.
    func computeAlignedReorg() {
        guard isVisualReorgActive else {
            alignedRows = []
            displayOrderMap = nil
            return
        }

        // Visual reorg is incompatible with sequential diff
        guard !(settings?.sequentialDiff ?? false) else {
            alignedRows = []
            displayOrderMap = nil
            return
        }

        let options = settings?.diffOptions ?? .default
        let (rows, map) = AlignedReorgEngine.computeAlignedRowsWithMap(
            leftFile: leftFile,
            rightFile: rightFile,
            options: options
        )
        alignedRows = rows
        displayOrderMap = map
    }

    // MARK: - Debounced Re-Diff

    private func scheduleReDiff() {
        reDiffTask?.cancel()
        reDiffTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.debounceInterval ?? 0)
            } catch {
                return  // Cancelled or other error — bail out
            }
            self?.reDiff()
        }
    }

    // MARK: - Diff Stats

    struct DiffStats {
        let equal: Int
        let modified: Int
        let leftOnly: Int
        let rightOnly: Int

        var totalDiffs: Int { modified + leftOnly + rightOnly }

        static let empty = DiffStats(equal: 0, modified: 0, leftOnly: 0, rightOnly: 0)

        var summary: String {
            var parts: [String] = []
            if modified > 0 { parts.append("\(modified) modified") }
            if leftOnly > 0 { parts.append("\(leftOnly) removed") }
            if rightOnly > 0 { parts.append("\(rightOnly) added") }
            if parts.isEmpty { return "Identical" }
            return parts.joined(separator: ", ")
        }
    }

    // MARK: - Merge Algorithm

    /// Builds the flat row array by merging DiffEngine results with context lines.
    func computeRows() {
        let options = settings?.diffOptions ?? .default
        let diffResults = DiffEngine.diff(left: leftFile, right: rightFile, options: options)

        // Sequential mode: all entries become diff rows (no context pairing)
        if options.diffMode == .sequential {
            rows = diffResults.map { result in
                ComparisonRow(
                    rowType: .diff,
                    leftEntry: result.leftEntry,
                    rightEntry: result.rightEntry,
                    diffCategory: result.category,
                    contextCategory: nil
                )
            }
            computeStats(from: diffResults)
            updateVisibleRows()
            return
        }

        // Build lookup: key → DiffResult
        var diffByKey: [String: DiffResult] = [:]
        var rightOnlyResults: [DiffResult] = []

        for result in diffResults {
            if let key = result.leftEntry?.key {
                diffByKey[key] = result
            } else if result.category == .rightOnly, let key = result.rightEntry?.key {
                diffByKey[key] = result
                rightOnlyResults.append(result)
            }
        }

        var merged: [ComparisonRow] = []
        var emittedLeftKeys: Set<String> = []

        let rightEntries = rightFile.entries

        // Build right context list for content-aware matching
        let rightContextEntries: [(index: Int, entry: EnvEntry)] = rightEntries.enumerated()
            .filter { $0.element.type != .keyValue }
            .map { (index: $0.offset, entry: $0.element) }
        var matchedRightContextIndices: Set<Int> = []

        // Phase 1: Walk left file entries in order
        for entry in leftFile.entries {
            switch entry.type {
            case .keyValue:
                guard let key = entry.key, !emittedLeftKeys.contains(key) else { continue }
                emittedLeftKeys.insert(key)

                if let diff = diffByKey[key] {
                    merged.append(ComparisonRow(
                        rowType: .diff,
                        leftEntry: diff.leftEntry,
                        rightEntry: diff.rightEntry,
                        diffCategory: diff.category,
                        contextCategory: nil
                    ))
                }

            case .comment, .blank, .malformed:
                let (rightContext, contextCat) = findMatchingRightContext(
                    leftEntry: entry,
                    rightContextEntries: rightContextEntries,
                    matchedIndices: &matchedRightContextIndices
                )
                merged.append(ComparisonRow(
                    rowType: .context,
                    leftEntry: entry,
                    rightEntry: rightContext,
                    diffCategory: nil,
                    contextCategory: contextCat
                ))
            }
        }

        // Phase 2: Append right-only diff rows
        for result in rightOnlyResults {
            merged.append(ComparisonRow(
                rowType: .diff,
                leftEntry: nil,
                rightEntry: result.rightEntry,
                diffCategory: .rightOnly,
                contextCategory: nil
            ))
        }

        // Phase 3: Append unmatched right context lines
        for item in rightContextEntries where !matchedRightContextIndices.contains(item.index) {
            merged.append(ComparisonRow(
                rowType: .context,
                leftEntry: nil,
                rightEntry: item.entry,
                diffCategory: nil,
                contextCategory: .rightOnly
            ))
        }

        rows = merged
        computeStats(from: diffResults)
        updateVisibleRows()
    }

    // MARK: - Private

    private func findMatchingRightContext(
        leftEntry: EnvEntry,
        rightContextEntries: [(index: Int, entry: EnvEntry)],
        matchedIndices: inout Set<Int>
    ) -> (EnvEntry?, ComparisonRow.ContextCategory) {
        let candidates = rightContextEntries.filter { !matchedIndices.contains($0.index) }
        let nearby = Array(candidates.prefix(5))

        // Exact content match first
        if let match = nearby.first(where: { $0.entry.rawLine == leftEntry.rawLine }) {
            matchedIndices.insert(match.index)
            return (match.entry, .equal)
        }
        // Same type, different content
        if let match = nearby.first(where: { $0.entry.type == leftEntry.type }) {
            matchedIndices.insert(match.index)
            return (match.entry, .modified)
        }
        return (nil, .leftOnly)
    }

    private func computeStats(from results: [DiffResult]) {
        var equal = 0, modified = 0, leftOnly = 0, rightOnly = 0
        for r in results {
            switch r.category {
            case .equal: equal += 1
            case .modified: modified += 1
            case .leftOnly: leftOnly += 1
            case .rightOnly: rightOnly += 1
            }
        }
        diffStats = DiffStats(equal: equal, modified: modified, leftOnly: leftOnly, rightOnly: rightOnly)
    }
}
