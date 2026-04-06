import SwiftUI

/// Encapsulates search state and match logic for the comparison view.
/// Decoupled from rows — callers pass row data when triggering search.
@MainActor
@Observable
final class SearchState {

    // MARK: - State

    /// Current search query.
    var searchText: String = "" {
        didSet { onSearchChanged?() }
    }

    /// Whether search bar is visible.
    var isSearchActive: Bool = false

    /// Which side search is scoped to (nil = both).
    var searchSide: PanelSide? {
        didSet { onSearchChanged?() }
    }

    /// All matching row indices.
    private(set) var searchMatches: [SearchMatch] = []

    /// Current match index (cycles through searchMatches).
    var currentMatchIndex: Int = 0

    /// Callback invoked when searchText or searchSide changes, so the VM can trigger performSearch.
    var onSearchChanged: (() -> Void)?

    // MARK: - Types

    /// A search match result.
    struct SearchMatch: Equatable {
        let rowIndex: Int
        let side: PanelSide
    }

    // MARK: - Computed

    /// Number of search matches.
    var searchMatchCount: Int { searchMatches.count }

    /// Current match (for highlight and scroll).
    var currentMatch: SearchMatch? {
        guard !searchMatches.isEmpty else { return nil }
        let idx = currentMatchIndex % searchMatches.count
        return searchMatches[idx]
    }

    // MARK: - Navigation

    /// Move to next match. Returns the new current match for scroll handling.
    @discardableResult
    func nextMatch() -> SearchMatch? {
        guard !searchMatches.isEmpty else { return nil }
        currentMatchIndex = (currentMatchIndex + 1) % searchMatches.count
        return currentMatch
    }

    /// Move to previous match. Returns the new current match for scroll handling.
    @discardableResult
    func previousMatch() -> SearchMatch? {
        guard !searchMatches.isEmpty else { return nil }
        currentMatchIndex = (currentMatchIndex - 1 + searchMatches.count) % searchMatches.count
        return currentMatch
    }

    /// Clear all search state.
    func clear() {
        searchText = ""
        searchMatches = []
        currentMatchIndex = 0
        isSearchActive = false
    }

    // MARK: - Search Execution

    /// Perform search across normal rows.
    func performSearch(rows: [ComparisonRow]) {
        guard !searchText.isEmpty else {
            searchMatches = []
            currentMatchIndex = 0
            return
        }

        let query = searchText.lowercased()
        var matches: [SearchMatch] = []

        for (index, row) in rows.enumerated() {
            if searchSide == nil || searchSide == .left {
                if let entry = row.leftEntry,
                   entry.rawLine.lowercased().contains(query) {
                    matches.append(SearchMatch(rowIndex: index, side: .left))
                }
            }
            if searchSide == nil || searchSide == .right {
                if let entry = row.rightEntry,
                   entry.rawLine.lowercased().contains(query) {
                    if matches.last?.rowIndex != index || matches.last?.side != .right {
                        matches.append(SearchMatch(rowIndex: index, side: .right))
                    }
                }
            }
        }

        searchMatches = matches
        currentMatchIndex = 0
    }

    /// Perform search across aligned rows (visual reorg mode).
    func performSearch(alignedRows: [AlignedRow]) {
        guard !searchText.isEmpty else {
            searchMatches = []
            currentMatchIndex = 0
            return
        }

        let query = searchText.lowercased()
        var matches: [SearchMatch] = []

        for (index, row) in alignedRows.enumerated() {
            if searchSide == nil || searchSide == .left {
                if let entry = row.leftEntry,
                   entry.rawLine.lowercased().contains(query) {
                    matches.append(SearchMatch(rowIndex: index, side: .left))
                }
            }
            if searchSide == nil || searchSide == .right {
                if let entry = row.rightEntry,
                   entry.rawLine.lowercased().contains(query) {
                    if matches.last?.rowIndex != index || matches.last?.side != .right {
                        matches.append(SearchMatch(rowIndex: index, side: .right))
                    }
                }
            }
        }

        searchMatches = matches
        currentMatchIndex = 0
    }
}
