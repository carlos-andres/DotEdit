import Foundation
import Testing
@testable import DotEdit

@Suite("Context Diff Matching")
struct ContextDiffTests {

    // MARK: - Helpers

    @MainActor
    private func makeVM(left: String, right: String) -> ComparisonViewModel {
        ComparisonViewModel(
            leftFile: EnvParser.parse(content: left, filePath: "/tmp/left.env"),
            rightFile: EnvParser.parse(content: right, filePath: "/tmp/right.env")
        )
    }

    @MainActor
    private func contextRows(_ vm: ComparisonViewModel) -> [ComparisonRow] {
        vm.rows.filter { $0.rowType == .context }
    }

    // MARK: - Tests

    @Test("Identical comments matched as equal")
    @MainActor func identicalComments() {
        let vm = makeVM(
            left: "# Database config\nDB_HOST=localhost",
            right: "# Database config\nDB_HOST=localhost"
        )
        let contexts = contextRows(vm)
        #expect(contexts.count == 1)
        #expect(contexts[0].contextCategory == .equal)
        #expect(contexts[0].leftEntry?.rawLine == "# Database config")
        #expect(contexts[0].rightEntry?.rawLine == "# Database config")
    }

    @Test("Different comments matched as modified")
    @MainActor func differentComments() {
        let vm = makeVM(
            left: "# Dev config\nDB_HOST=localhost",
            right: "# Prod config\nDB_HOST=localhost"
        )
        let contexts = contextRows(vm)
        #expect(contexts.count == 1)
        #expect(contexts[0].contextCategory == .modified)
    }

    @Test("Left-only comment")
    @MainActor func leftOnlyComment() {
        let vm = makeVM(
            left: "# Only on left\nDB_HOST=localhost",
            right: "DB_HOST=localhost"
        )
        let contexts = contextRows(vm)
        #expect(contexts.count == 1)
        #expect(contexts[0].contextCategory == .leftOnly)
        #expect(contexts[0].leftEntry != nil)
        #expect(contexts[0].rightEntry == nil)
    }

    @Test("Right-only comment")
    @MainActor func rightOnlyComment() {
        let vm = makeVM(
            left: "DB_HOST=localhost",
            right: "# Only on right\nDB_HOST=localhost"
        )
        let contexts = contextRows(vm)
        #expect(contexts.count == 1)
        #expect(contexts[0].contextCategory == .rightOnly)
        #expect(contexts[0].leftEntry == nil)
        #expect(contexts[0].rightEntry != nil)
    }

    @Test("Blank lines matched as equal")
    @MainActor func blankLinesEqual() {
        let vm = makeVM(
            left: "A=1\n\nB=2",
            right: "A=1\n\nB=2"
        )
        let contexts = contextRows(vm)
        #expect(contexts.count == 1)
        #expect(contexts[0].contextCategory == .equal)
    }

    @Test("Multiple comments with mixed matches")
    @MainActor func multipleComments() {
        let vm = makeVM(
            left: "# Same\n# Left only\nA=1",
            right: "# Same\nA=1"
        )
        let contexts = contextRows(vm)
        #expect(contexts.count == 2)
        // First comment matches
        let same = contexts.first { $0.leftEntry?.rawLine == "# Same" }
        #expect(same?.contextCategory == .equal)
        // Second comment is left-only
        let leftOnly = contexts.first { $0.leftEntry?.rawLine == "# Left only" }
        #expect(leftOnly?.contextCategory == .leftOnly)
    }
}
