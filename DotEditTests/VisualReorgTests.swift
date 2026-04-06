import Foundation
import Testing
@testable import DotEdit

@Suite("VisualReorg VM Integration")
struct VisualReorgTests {

    // MARK: - Helpers

    private func parse(_ content: String) -> EnvFile {
        EnvParser.parse(content: content, filePath: "test")
    }

    @MainActor
    private func makeVM(left: String, right: String) -> ComparisonViewModel {
        ComparisonViewModel(
            leftFile: parse(left),
            rightFile: parse(right)
        )
    }

    // MARK: - Toggle Produces Aligned Rows

    @Test("Toggle ON populates alignedRows")
    @MainActor
    func toggleProducesAlignedRows() {
        let vm = makeVM(
            left: "API_KEY=abc\nDB_HOST=localhost",
            right: "API_KEY=xyz\nDB_HOST=remote"
        )

        #expect(vm.alignedRows.isEmpty)

        vm.isVisualReorgActive = true

        #expect(!vm.alignedRows.isEmpty)
        #expect(vm.alignedRows.count == 2)
    }

    // MARK: - Toggle Off

    @Test("Toggle OFF clears alignedRows")
    @MainActor
    func toggleOff() {
        let vm = makeVM(
            left: "API_KEY=abc\nDB_HOST=localhost",
            right: "API_KEY=xyz\nDB_HOST=remote"
        )

        vm.isVisualReorgActive = true
        #expect(!vm.alignedRows.isEmpty)

        vm.isVisualReorgActive = false
        #expect(vm.alignedRows.isEmpty)
    }

    // MARK: - Does Not Dirty

    @Test("Toggle doesn't mark dirty")
    @MainActor
    func doesNotDirty() {
        let vm = makeVM(
            left: "API_KEY=abc",
            right: "API_KEY=xyz"
        )

        vm.isVisualReorgActive = true
        #expect(!vm.isLeftDirty)
        #expect(!vm.isRightDirty)
    }

    // MARK: - Collapse With Reorg

    @Test("visibleAlignedRows hides equal rows when collapsed")
    @MainActor
    func collapseWithReorg() {
        let vm = makeVM(
            left: "API_KEY=abc\nDB_HOST=localhost",
            right: "API_KEY=abc\nDB_HOST=remote"
        )

        vm.isVisualReorgActive = true

        // One equal (API_KEY), one modified (DB_HOST)
        #expect(vm.alignedRows.count == 2)

        vm.isCollapsed = true
        #expect(vm.visibleAlignedRows.count == 1) // only modified
        #expect(vm.collapsedAlignedCount == 1)
    }

    // MARK: - ReDiff Refreshes Aligned

    @Test("reDiff re-triggers aligned computation")
    @MainActor
    func reDiffRefreshesAligned() {
        let vm = makeVM(
            left: "API_KEY=abc\nDB_HOST=localhost",
            right: "API_KEY=xyz\nDB_HOST=remote"
        )

        vm.isVisualReorgActive = true
        let countBefore = vm.alignedRows.count

        // Edit a line — triggers reDiff
        vm.updateLine(at: 0, to: "API_KEY=changed", side: .left)
        // Force reDiff (normally debounced)
        vm.reDiff()

        #expect(vm.alignedRows.count == countBefore)
        // The modified value should be reflected
        let apiRow = vm.alignedRows.first { $0.leftEntry?.key == "API_KEY" }
        #expect(apiRow?.leftEntry?.value == "changed")
    }

    // MARK: - Edit Maps Back

    @Test("Edit while reorg active maps to original line position")
    @MainActor
    func editMapsBack() {
        let vm = makeVM(
            left: "DB_HOST=localhost\nAPI_KEY=abc",
            right: "DB_HOST=remote\nAPI_KEY=xyz"
        )

        vm.isVisualReorgActive = true

        // Aligned rows reorder: API before DB alphabetically
        // But editing uses original line positions via leftLines/rightLines
        vm.updateLine(at: 1, to: "API_KEY=edited", side: .left) // line 2 in original = API_KEY
        vm.reDiff()

        #expect(vm.isLeftDirty)
        let apiRow = vm.alignedRows.first { $0.leftEntry?.key == "API_KEY" }
        #expect(apiRow?.leftEntry?.value == "edited")
    }
}
