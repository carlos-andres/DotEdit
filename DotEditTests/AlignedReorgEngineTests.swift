import Foundation
import Testing
@testable import DotEdit

@Suite("AlignedReorgEngine")
struct AlignedReorgEngineTests {

    // MARK: - Helpers

    private func parse(_ content: String) -> EnvFile {
        EnvParser.parse(content: content, filePath: "test")
    }

    // MARK: - Basic Alignment

    @Test("Groups matching keys side-by-side by prefix, sorted alphabetically")
    func basicAlignment() {
        let left = parse("API_KEY=abc\nAPI_URL=http\nDB_HOST=localhost\nDB_PORT=5432")
        let right = parse("API_KEY=xyz\nAPI_URL=http\nDB_HOST=remote\nDB_PORT=3306")

        let rows = AlignedReorgEngine.computeAlignedRows(leftFile: left, rightFile: right)

        // Should have 4 rows in 2 groups (API, DB), sorted alphabetically by group then by key
        #expect(rows.count == 4)

        // API group first (alphabetically before DB)
        #expect(rows[0].prefixGroup == "API")
        #expect(rows[0].leftEntry?.key == "API_KEY")
        #expect(rows[0].rightEntry?.key == "API_KEY")

        #expect(rows[1].prefixGroup == "API")
        #expect(rows[1].leftEntry?.key == "API_URL")
        #expect(rows[1].rightEntry?.key == "API_URL")

        // DB group
        #expect(rows[2].prefixGroup == "DB")
        #expect(rows[2].leftEntry?.key == "DB_HOST")
        #expect(rows[2].rightEntry?.key == "DB_HOST")

        #expect(rows[3].prefixGroup == "DB")
        #expect(rows[3].leftEntry?.key == "DB_PORT")
    }

    // MARK: - Gap Alignment

    @Test("Creates gap rows for keys only on one side")
    func gapAlignment() {
        let left = parse("DB_HOST=localhost\nDB_PORT=5432")
        let right = parse("DB_HOST=remote\nDB_LOCK=true")

        let rows = AlignedReorgEngine.computeAlignedRows(leftFile: left, rightFile: right)

        // DB_HOST: both sides (equal or modified)
        // DB_LOCK: right only (left gap)
        // DB_PORT: left only (right gap)
        #expect(rows.count == 3)

        // All in DB group, sorted alphabetically: DB_HOST, DB_LOCK, DB_PORT
        let hostRow = rows.first { $0.leftEntry?.key == "DB_HOST" || $0.rightEntry?.key == "DB_HOST" }
        #expect(hostRow != nil)
        #expect(hostRow?.isLeftGap == false)
        #expect(hostRow?.isRightGap == false)

        let lockRow = rows.first { $0.rightEntry?.key == "DB_LOCK" }
        #expect(lockRow != nil)
        #expect(lockRow?.isLeftGap == true)   // left side is gap
        #expect(lockRow?.diffCategory == .rightOnly)

        let portRow = rows.first { $0.leftEntry?.key == "DB_PORT" }
        #expect(portRow != nil)
        #expect(portRow?.isRightGap == true)  // right side is gap
        #expect(portRow?.diffCategory == .leftOnly)
    }

    // MARK: - Hides Context Lines

    @Test("No comment or blank rows in output")
    func hidesContextLines() {
        let left = parse("# Database\nDB_HOST=localhost\n\n# API\nAPI_KEY=abc")
        let right = parse("# Settings\nDB_HOST=remote\nAPI_KEY=xyz")

        let rows = AlignedReorgEngine.computeAlignedRows(leftFile: left, rightFile: right)

        // Only key-value entries should appear
        for row in rows {
            if let entry = row.leftEntry {
                #expect(entry.type == .keyValue)
            }
            if let entry = row.rightEntry {
                #expect(entry.type == .keyValue)
            }
        }
        #expect(rows.count == 2) // API_KEY, DB_HOST
    }

    // MARK: - Malformed Lines

    @Test("Malformed lines go to OTHER group")
    func malformedInOther() {
        let left = parse("DB_HOST=localhost\nthis is malformed")
        let right = parse("DB_HOST=remote")

        let rows = AlignedReorgEngine.computeAlignedRows(leftFile: left, rightFile: right)

        // DB_HOST matched + malformed shows in OTHER group (Q-006 / DEC-038)
        let dbRow = rows.first { $0.leftEntry?.key == "DB_HOST" }
        #expect(dbRow != nil)
        #expect(rows.count == 2) // DB_HOST + malformed
        let malformedRow = rows.first { $0.leftEntry?.type == .malformed }
        #expect(malformedRow != nil)
        #expect(malformedRow?.prefixGroup == "OTHER")
        #expect(malformedRow?.diffCategory == .leftOnly)
    }

    // MARK: - Case Insensitive

    @Test("Case-insensitive matching produces matched pair")
    func caseInsensitive() {
        let left = parse("db_host=localhost")
        let right = parse("DB_HOST=remote")

        let options = DiffEngine.Options(caseInsensitiveKeys: true)
        let rows = AlignedReorgEngine.computeAlignedRows(leftFile: left, rightFile: right, options: options)

        #expect(rows.count == 1)
        #expect(rows[0].diffCategory == .modified)
        #expect(rows[0].leftEntry?.key == "db_host")
        #expect(rows[0].rightEntry?.key == "DB_HOST")
    }

    // MARK: - Sorted Within Group

    @Test("Keys within prefix group are sorted alphabetically")
    func sortedWithinGroup() {
        let left = parse("DB_PORT=5432\nDB_HOST=localhost\nDB_PASS=sample\nDB_NAME=mydb")
        let right = parse("DB_HOST=remote\nDB_PORT=3306\nDB_NAME=other\nDB_PASS=pwd")

        let rows = AlignedReorgEngine.computeAlignedRows(leftFile: left, rightFile: right)

        #expect(rows.count == 4)
        // Should be sorted: DB_HOST, DB_NAME, DB_PASS, DB_PORT
        #expect(rows[0].leftEntry?.key == "DB_HOST")
        #expect(rows[1].leftEntry?.key == "DB_NAME")
        #expect(rows[2].leftEntry?.key == "DB_PASS")
        #expect(rows[3].leftEntry?.key == "DB_PORT")
    }

    // MARK: - Mixed Conventions

    @Test("Per-panel convention detection with mixed conventions")
    func mixedConventions() {
        // Left: 2 SCREAMING_SNAKE + 1 dotNotation → dominant is SCREAMING_SNAKE
        let left = parse("DB_HOST=localhost\nDB_PORT=3306\napi.key=abc")
        let right = parse("DB_HOST=remote\nAPI_KEY=xyz")

        let rows = AlignedReorgEngine.computeAlignedRows(leftFile: left, rightFile: right)

        // DB_HOST matches across panels
        let dbRow = rows.first { $0.leftEntry?.key == "DB_HOST" || $0.rightEntry?.key == "DB_HOST" }
        #expect(dbRow != nil)
        #expect(dbRow?.leftEntry != nil)
        #expect(dbRow?.rightEntry != nil)
    }

    // MARK: - Display Order Map

    @Test("Returns correct mappings with hidden entry IDs")
    func displayOrderMap() {
        let left = parse("# Comment\nDB_HOST=localhost\n\nAPI_KEY=abc")
        let right = parse("DB_HOST=remote\nAPI_KEY=xyz")

        let (rows, map) = AlignedReorgEngine.computeAlignedRowsWithMap(leftFile: left, rightFile: right)

        #expect(rows.count == 2) // API_KEY, DB_HOST

        // Hidden entries should include the comment and blank from left
        #expect(map.hiddenEntryIDs.count >= 2) // comment + blank

        // Gap indices should be empty (both keys exist on both sides)
        #expect(map.gapIndices.isEmpty)

        // Visual-to-original mappings for all rows
        #expect(map.visualToOriginal.count == rows.count)
    }
}
