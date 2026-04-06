import Foundation
import Testing
@testable import DotEdit

@Suite("Search & Warnings")
struct SearchAndWarningsTests {

    // MARK: - Helpers

    @MainActor
    private func makeVM(left: String, right: String) -> ComparisonViewModel {
        ComparisonViewModel(
            leftFile: EnvParser.parse(content: left, filePath: "/tmp/left.env"),
            rightFile: EnvParser.parse(content: right, filePath: "/tmp/right.env")
        )
    }

    // MARK: - Search: Basic Matching

    @Test("Search finds matches in left entries")
    @MainActor func searchLeft() {
        let vm = makeVM(left: "API_KEY=abc\nDB_HOST=localhost", right: "OTHER=1")

        vm.search.searchText = "API"
        #expect(vm.search.searchMatchCount == 1)
        #expect(vm.search.searchMatches[0].side == .left)
    }

    @Test("Search finds matches in right entries")
    @MainActor func searchRight() {
        let vm = makeVM(left: "A=1", right: "SECRET_KEY=sample\nDB_URL=pg")

        vm.search.searchText = "SECRET"
        #expect(vm.search.searchMatchCount == 1)
        #expect(vm.search.searchMatches[0].side == .right)
    }

    @Test("Search is case-insensitive")
    @MainActor func searchCaseInsensitive() {
        let vm = makeVM(left: "API_KEY=abc", right: "X=1")

        vm.search.searchText = "api_key"
        #expect(vm.search.searchMatchCount == 1)
    }

    @Test("Search returns empty for no matches")
    @MainActor func searchNoMatches() {
        let vm = makeVM(left: "A=1\nB=2", right: "C=3\nD=4")

        vm.search.searchText = "ZZZZZ"
        #expect(vm.search.searchMatchCount == 0)
        #expect(vm.search.currentMatch == nil)
    }

    @Test("Search with empty string clears matches")
    @MainActor func searchEmptyClears() {
        let vm = makeVM(left: "A=1", right: "B=2")

        vm.search.searchText = "A"
        #expect(vm.search.searchMatchCount > 0)

        vm.search.searchText = ""
        #expect(vm.search.searchMatchCount == 0)
    }

    // MARK: - Search: Scoping

    @Test("Search scoped to left only")
    @MainActor func searchScopedLeft() {
        let vm = makeVM(left: "KEY=abc", right: "KEY=xyz")

        vm.search.searchSide = .left
        vm.search.searchText = "KEY"
        #expect(vm.search.searchMatchCount == 1)
        #expect(vm.search.searchMatches[0].side == .left)
    }

    @Test("Search scoped to right only")
    @MainActor func searchScopedRight() {
        let vm = makeVM(left: "KEY=abc", right: "KEY=xyz")

        vm.search.searchSide = .right
        vm.search.searchText = "KEY"
        #expect(vm.search.searchMatchCount == 1)
        #expect(vm.search.searchMatches[0].side == .right)
    }

    // MARK: - Search: Navigation

    @Test("Next match cycles through results")
    @MainActor func nextMatchCycles() {
        // Use different keys so each gets its own row in the diff
        let vm = makeVM(left: "APP_NAME=foo\nAPP_HOST=bar\nAPP_PORT=3000", right: "X=1")

        vm.search.searchText = "APP"
        let count = vm.search.searchMatchCount
        #expect(count == 3)
        #expect(vm.search.currentMatchIndex == 0)

        vm.nextMatch()
        #expect(vm.search.currentMatchIndex == 1)

        vm.nextMatch()
        #expect(vm.search.currentMatchIndex == 2)

        vm.nextMatch()
        #expect(vm.search.currentMatchIndex == 0) // wraps
    }

    @Test("Previous match cycles backwards")
    @MainActor func previousMatchCycles() {
        let vm = makeVM(left: "APP_NAME=foo\nAPP_HOST=bar", right: "X=1")

        vm.search.searchText = "APP"
        #expect(vm.search.currentMatchIndex == 0)

        vm.previousMatch()
        #expect(vm.search.currentMatchIndex == 1) // wraps to last
    }

    @Test("Clear search resets all state")
    @MainActor func clearSearchResetsState() {
        let vm = makeVM(left: "A=1", right: "B=2")

        vm.search.isSearchActive = true
        vm.search.searchText = "A"
        vm.nextMatch()

        vm.clearSearch()
        #expect(vm.search.searchText.isEmpty)
        #expect(vm.search.searchMatches.isEmpty)
        #expect(vm.search.currentMatchIndex == 0)
        #expect(vm.search.isSearchActive == false)
    }

    // MARK: - Search: Auto-uncollapse

    @Test("Search auto-uncollapses when results found")
    @MainActor func searchAutoUncollapses() {
        let vm = makeVM(left: "A=1\nB=2", right: "A=1\nB=changed")

        vm.isCollapsed = true
        #expect(vm.isCollapsed == true)

        // Search for A which is in an equal (collapsed) row
        vm.search.searchText = "A"
        #expect(vm.isCollapsed == false)
    }

    // MARK: - Warning: File-level Aggregation

    @Test("Warning count aggregates both files")
    @MainActor func warningCountBothFiles() {
        // Duplicate keys generate warnings
        let vm = makeVM(left: "A=1\nA=2", right: "B=1\nB=2")

        // Both files have duplicate key warnings
        #expect(vm.warningCount >= 2)
    }

    @Test("No warnings for clean files")
    @MainActor func noWarningsCleanFiles() {
        let vm = makeVM(left: "A=1\nB=2", right: "C=3\nD=4")

        #expect(vm.warningCount == 0)
    }

    @Test("Malformed line generates warning")
    @MainActor func malformedLineWarning() {
        let vm = makeVM(left: "not a valid line without equals", right: "A=1")

        let leftWarnings = vm.leftFile.allWarnings
        let malformed = leftWarnings.filter { $0.type == .malformedLine }
        #expect(malformed.count == 1)
    }

    @Test("Duplicate key generates warning for all occurrences")
    @MainActor func duplicateKeyWarning() {
        let vm = makeVM(left: "DB=one\nDB=two", right: "A=1")

        let leftWarnings = vm.leftFile.allWarnings
        let duplicates = leftWarnings.filter { $0.type == .duplicateKey }
        // Parser flags all occurrences of a duplicate key
        #expect(duplicates.count == 2)
    }

    @Test("Warning has line numbers for duplicate entries")
    @MainActor func warningLineNumber() {
        let vm = makeVM(left: "X=ok\nA=1\nA=2", right: "Y=1")

        let leftWarnings = vm.leftFile.allWarnings
        let dupWarnings = leftWarnings.filter { $0.type == .duplicateKey }
        let lineNumbers = dupWarnings.compactMap(\.lineNumber).sorted()
        #expect(lineNumbers.contains(2))
        #expect(lineNumbers.contains(3))
    }

    // MARK: - Warning: allWarnings combines both sides

    @Test("allWarnings includes warnings from both files")
    @MainActor func allWarningsBothSides() {
        let vm = makeVM(left: "A=1\nA=2", right: "B=1\nB=2")

        let all = vm.allWarnings
        let leftDups = all.filter { $0.message.contains("A") }
        let rightDups = all.filter { $0.message.contains("B") }
        #expect(!leftDups.isEmpty)
        #expect(!rightDups.isEmpty)
    }
}
