import Foundation
import Testing
@testable import DotEdit

@Suite("Collapse & Dedup")
struct CollapseAndDedupTests {

    // MARK: - Helpers

    private func parse(_ content: String) -> EnvFile {
        EnvParser.parse(content: content, filePath: "test")
    }

    @MainActor
    private func makeVM(left: String, right: String) -> ComparisonViewModel {
        ComparisonViewModel(
            leftFile: EnvParser.parse(content: left, filePath: "/tmp/left.env"),
            rightFile: EnvParser.parse(content: right, filePath: "/tmp/right.env")
        )
    }

    // MARK: - Collapse

    @Test("Collapse filters out equal diff rows")
    @MainActor func collapseFiltersEqual() {
        let vm = makeVM(left: "A=1\nB=2\nC=3", right: "A=1\nB=changed\nC=3")

        #expect(vm.isCollapsed == false)
        #expect(vm.visibleRows.count == vm.rows.count)

        vm.isCollapsed = true

        // A=1 and C=3 are equal, should be hidden
        let visible = vm.visibleRows
        let diffRows = visible.filter { $0.rowType == .diff }
        #expect(diffRows.count == 1) // only B (modified)
        #expect(diffRows.first?.leftEntry?.key == "B")
    }

    @Test("Collapsed count is accurate")
    @MainActor func collapsedCount() {
        let vm = makeVM(left: "A=1\nB=2\nC=3", right: "A=1\nB=changed\nC=3")

        #expect(vm.collapsedCount == 0)

        vm.isCollapsed = true
        #expect(vm.collapsedCount == 2) // A and C hidden
    }

    @Test("Uncollapse restores all rows")
    @MainActor func uncollapseRestores() {
        let vm = makeVM(left: "A=1\nB=2", right: "A=1\nB=changed")
        let allCount = vm.rows.count

        vm.isCollapsed = true
        #expect(vm.visibleRows.count < allCount)

        vm.isCollapsed = false
        #expect(vm.visibleRows.count == allCount)
    }

    @Test("Collapse hides equal context rows, keeps modified")
    @MainActor func collapseFiltersContext() {
        let vm = makeVM(left: "# same\n# different\nA=1", right: "# same\n# changed\nA=1")

        vm.isCollapsed = true
        let contextRows = vm.visibleRows.filter { $0.rowType == .context }
        // Equal context ("# same") is hidden, modified context is shown
        #expect(contextRows.count == 1)
        #expect(contextRows[0].contextCategory == .modified)
    }

    @Test("Collapse with all different rows hides nothing")
    @MainActor func collapseAllDifferent() {
        let vm = makeVM(left: "A=1\nB=2", right: "A=changed\nB=changed")

        vm.isCollapsed = true
        #expect(vm.collapsedCount == 0)
        #expect(vm.visibleRows.count == vm.rows.count)
    }

    @Test("Collapse with all identical rows hides all diff rows")
    @MainActor func collapseAllIdentical() {
        let vm = makeVM(left: "A=1\nB=2", right: "A=1\nB=2")

        vm.isCollapsed = true
        let diffRows = vm.visibleRows.filter { $0.rowType == .diff }
        #expect(diffRows.isEmpty)
        #expect(vm.collapsedCount == 2)
    }

    // MARK: - Dedup

    @Test("Dedup removes duplicate keys keeping first occurrence")
    @MainActor func dedupKeepsFirst() {
        let vm = makeVM(left: "A=1\nB=2\nA=3", right: "X=1")

        let result = vm.dedup(side: .left)
        #expect(result.removedCount == 1)
        #expect(result.removedKeys == ["A"])

        // First A=1 kept, second A=3 removed
        #expect(vm.leftLines.count == 2)
        #expect(vm.leftLines[0] == "A=1")
        #expect(vm.leftLines[1] == "B=2")
    }

    @Test("Dedup with no duplicates returns zero")
    @MainActor func dedupNoDuplicates() {
        let vm = makeVM(left: "A=1\nB=2\nC=3", right: "X=1")

        let result = vm.dedup(side: .left)
        #expect(result.removedCount == 0)
        #expect(result.removedKeys.isEmpty)
    }

    @Test("Dedup marks panel dirty")
    @MainActor func dedupMarksDirty() {
        let vm = makeVM(left: "A=1\nA=2", right: "X=1")

        #expect(vm.isLeftDirty == false)
        _ = vm.dedup(side: .left)
        #expect(vm.isLeftDirty == true)
    }

    @Test("Dedup does not dirty panel when no duplicates")
    @MainActor func dedupNoDupsNoDirty() {
        let vm = makeVM(left: "A=1\nB=2", right: "X=1")

        _ = vm.dedup(side: .left)
        #expect(vm.isLeftDirty == false)
    }

    @Test("Dedup on right panel works")
    @MainActor func dedupRight() {
        let vm = makeVM(left: "X=1", right: "A=1\nB=2\nA=3\nB=4")

        let result = vm.dedup(side: .right)
        #expect(result.removedCount == 2)
        #expect(result.removedKeys.contains("A"))
        #expect(result.removedKeys.contains("B"))
        #expect(vm.rightLines.count == 2)
        #expect(vm.isRightDirty == true)
    }

    @Test("Dedup triggers re-diff")
    @MainActor func dedupReDiffs() {
        let vm = makeVM(left: "A=1\nA=2", right: "A=1")

        // Before dedup: left has duplicate, diff shows modified (A=1 vs A=1 = equal)
        _ = vm.dedup(side: .left)

        // After dedup: left has A=1 only, should be equal
        let equalRows = vm.rows.filter { $0.diffCategory == .equal }
        #expect(equalRows.count == 1)
    }

    @Test("Dedup with multiple duplicates of same key")
    @MainActor func dedupMultipleSameKey() {
        let vm = makeVM(left: "A=1\nA=2\nA=3\nA=4", right: "X=1")

        let result = vm.dedup(side: .left)
        #expect(result.removedCount == 3) // keep first, remove 3
        #expect(result.removedKeys == ["A"])
        #expect(vm.leftLines.count == 1)
        #expect(vm.leftLines[0] == "A=1")
    }
}
