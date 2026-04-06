import Foundation
import Testing
@testable import DotEdit

@Suite("ExternalChangeDiff (BL-004)")
struct ExternalChangeDiffTests {

    // MARK: - Helpers

    private func parse(_ content: String) -> EnvFile {
        EnvParser.parse(content: content, filePath: "/tmp/test.env")
    }

    /// Write content to a temp file and return its URL.
    private func writeTempFile(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dotedit-test-\(UUID().uuidString).env")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Modified Key

    @Test("Modified key produces correct stats and change detail")
    func modifiedKey() async throws {
        let original = "API_KEY=old_value\nDB_HOST=localhost"
        let changed = "API_KEY=new_value\nDB_HOST=localhost"

        let url = try writeTempFile(changed)
        defer { try? FileManager.default.removeItem(at: url) }

        let left = parse(original)
        let right = parse(original)
        let vm = await ComparisonViewModel(leftFile: left, rightFile: right)

        let summary = try await vm.computeExternalChangeSummary(for: url, side: .left)

        #expect(summary.stats.modified == 1)
        #expect(summary.stats.equal == 1)
        #expect(summary.stats.leftOnly == 0)
        #expect(summary.stats.rightOnly == 0)
        #expect(summary.changes.count == 1)
        #expect(summary.changes[0].category == .modified)
        #expect(summary.changes[0].leftEntry?.key == "API_KEY")
        #expect(summary.sideLabel == "Left")
    }

    // MARK: - Added Key

    @Test("Added key appears as rightOnly")
    func addedKey() async throws {
        let original = "DB_HOST=localhost"
        let changed = "DB_HOST=localhost\nNEW_KEY=added"

        let url = try writeTempFile(changed)
        defer { try? FileManager.default.removeItem(at: url) }

        let left = parse(original)
        let right = parse(original)
        let vm = await ComparisonViewModel(leftFile: left, rightFile: right)

        let summary = try await vm.computeExternalChangeSummary(for: url, side: .left)

        #expect(summary.stats.rightOnly == 1)
        #expect(summary.changes.count == 1)
        #expect(summary.changes[0].category == .rightOnly)
        #expect(summary.changes[0].rightEntry?.key == "NEW_KEY")
    }

    // MARK: - Removed Key

    @Test("Removed key appears as leftOnly")
    func removedKey() async throws {
        let original = "A=1\nB=2\nC=3"
        let changed = "A=1\nC=3"

        let url = try writeTempFile(changed)
        defer { try? FileManager.default.removeItem(at: url) }

        let left = parse(original)
        let right = parse(original)
        let vm = await ComparisonViewModel(leftFile: left, rightFile: right)

        let summary = try await vm.computeExternalChangeSummary(for: url, side: .left)

        #expect(summary.stats.leftOnly == 1)
        #expect(summary.changes.count == 1)
        #expect(summary.changes[0].category == .leftOnly)
        #expect(summary.changes[0].leftEntry?.key == "B")
    }

    // MARK: - No Changes

    @Test("No changes produces empty results")
    func noChanges() async throws {
        let content = "X=1\nY=2"

        let url = try writeTempFile(content)
        defer { try? FileManager.default.removeItem(at: url) }

        let left = parse(content)
        let right = parse(content)
        let vm = await ComparisonViewModel(leftFile: left, rightFile: right)

        let summary = try await vm.computeExternalChangeSummary(for: url, side: .left)

        #expect(summary.stats.totalDiffs == 0)
        #expect(summary.changes.isEmpty)
    }

    // MARK: - Cap at 50

    @Test("Changes capped at 50")
    func cappedAt50() async throws {
        // Generate 60 unique keys that differ
        let originalLines = (1...60).map { "KEY_\($0)=old" }.joined(separator: "\n")
        let changedLines = (1...60).map { "KEY_\($0)=new" }.joined(separator: "\n")

        let url = try writeTempFile(changedLines)
        defer { try? FileManager.default.removeItem(at: url) }

        let left = parse(originalLines)
        let right = parse(originalLines)
        let vm = await ComparisonViewModel(leftFile: left, rightFile: right)

        let summary = try await vm.computeExternalChangeSummary(for: url, side: .left)

        #expect(summary.stats.modified == 60)
        #expect(summary.changes.count == 50)
    }

    // MARK: - Right Side

    @Test("Right side label is correct")
    func rightSideLabel() async throws {
        let content = "A=1"

        let url = try writeTempFile(content)
        defer { try? FileManager.default.removeItem(at: url) }

        let left = parse(content)
        let right = parse(content)
        let vm = await ComparisonViewModel(leftFile: left, rightFile: right)

        let summary = try await vm.computeExternalChangeSummary(for: url, side: .right)

        #expect(summary.sideLabel == "Right")
    }
}
