import Foundation
import Testing
@testable import DotEdit

@Suite("DiffEngine")
struct DiffEngineTests {

    // MARK: - Helpers

    private func parse(_ content: String) -> EnvFile {
        EnvParser.parse(content: content, filePath: "test")
    }

    // MARK: - Identical Files

    @Test("Identical files produce all equal results")
    func identicalFiles() {
        let content = "A=1\nB=2\nC=3"
        let left = parse(content)
        let right = parse(content)
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.count == 3)
        #expect(results.allSatisfy { $0.category == .equal })
    }

    // MARK: - Completely Different Files

    @Test("Completely different files produce leftOnly and rightOnly")
    func completelyDifferent() {
        let left = parse("A=1\nB=2")
        let right = parse("X=10\nY=20")
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.count == 4)
        let leftOnly = results.filter { $0.category == .leftOnly }
        let rightOnly = results.filter { $0.category == .rightOnly }
        #expect(leftOnly.count == 2)
        #expect(rightOnly.count == 2)

        // Left-only come first (left file order), then right-only
        #expect(results[0].category == .leftOnly)
        #expect(results[0].leftEntry?.key == "A")
        #expect(results[1].category == .leftOnly)
        #expect(results[1].leftEntry?.key == "B")
        #expect(results[2].category == .rightOnly)
        #expect(results[2].rightEntry?.key == "X")
        #expect(results[3].category == .rightOnly)
        #expect(results[3].rightEntry?.key == "Y")
    }

    // MARK: - Mixed Diffs

    @Test("Mixed equal, modified, leftOnly, rightOnly")
    func mixedDiff() {
        let left = parse("A=1\nB=2\nC=3")
        let right = parse("A=1\nB=changed\nD=4")
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.count == 4)

        let equal = results.filter { $0.category == .equal }
        let modified = results.filter { $0.category == .modified }
        let leftOnly = results.filter { $0.category == .leftOnly }
        let rightOnly = results.filter { $0.category == .rightOnly }

        #expect(equal.count == 1)
        #expect(equal[0].leftEntry?.key == "A")

        #expect(modified.count == 1)
        #expect(modified[0].leftEntry?.key == "B")
        #expect(modified[0].leftEntry?.value == "2")
        #expect(modified[0].rightEntry?.value == "changed")

        #expect(leftOnly.count == 1)
        #expect(leftOnly[0].leftEntry?.key == "C")

        #expect(rightOnly.count == 1)
        #expect(rightOnly[0].rightEntry?.key == "D")
    }

    // MARK: - Ordering

    @Test("Results ordered: matched pairs by left order, then right-only")
    func ordering() {
        let left = parse("C=3\nA=1\nB=2")
        let right = parse("B=2\nD=4\nA=1")
        let results = DiffEngine.diff(left: left, right: right)

        // C is leftOnly, A is equal, B is equal, D is rightOnly
        #expect(results.count == 4)
        // Matched pairs in left order: C(leftOnly), A(equal), B(equal)
        #expect(results[0].category == .leftOnly)
        #expect(results[0].leftEntry?.key == "C")
        #expect(results[1].category == .equal)
        #expect(results[1].leftEntry?.key == "A")
        #expect(results[2].category == .equal)
        #expect(results[2].leftEntry?.key == "B")
        // Right-only at end
        #expect(results[3].category == .rightOnly)
        #expect(results[3].rightEntry?.key == "D")
    }

    // MARK: - Duplicate Keys

    @Test("Duplicate keys match first occurrence only")
    func duplicateKeys() {
        let left = parse("KEY=first\nKEY=second")
        let right = parse("KEY=first")
        let results = DiffEngine.diff(left: left, right: right)

        // Only first occurrence of KEY matched
        #expect(results.count == 1)
        #expect(results[0].category == .equal)
        #expect(results[0].leftEntry?.value == "first")
    }

    @Test("Duplicate keys in right file match first occurrence")
    func duplicateKeysRight() {
        let left = parse("KEY=value")
        let right = parse("KEY=value\nKEY=other")
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.count == 1)
        #expect(results[0].category == .equal)
    }

    // MARK: - Empty Values vs Missing Keys

    @Test("Empty value is not the same as missing key")
    func emptyValueVsMissing() {
        let left = parse("KEY=")
        let right = parse("OTHER=value")
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.count == 2)
        #expect(results[0].category == .leftOnly)
        #expect(results[0].leftEntry?.key == "KEY")
        #expect(results[1].category == .rightOnly)
        #expect(results[1].rightEntry?.key == "OTHER")
    }

    @Test("Empty value vs non-empty value is modified")
    func emptyValueVsNonEmpty() {
        let left = parse("KEY=")
        let right = parse("KEY=value")
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.count == 1)
        #expect(results[0].category == .modified)
    }

    // MARK: - Case-Insensitive Mode

    @Test("Case-insensitive key matching")
    func caseInsensitive() {
        let left = parse("db_host=localhost")
        let right = parse("DB_HOST=localhost")
        let options = DiffEngine.Options(caseInsensitiveKeys: true)
        let results = DiffEngine.diff(left: left, right: right, options: options)

        #expect(results.count == 1)
        #expect(results[0].category == .equal)
    }

    @Test("Case-sensitive by default treats different cases as different keys")
    func caseSensitiveDefault() {
        let left = parse("db_host=localhost")
        let right = parse("DB_HOST=localhost")
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.count == 2)
        #expect(results[0].category == .leftOnly)
        #expect(results[1].category == .rightOnly)
    }

    @Test("Case-insensitive modified detection")
    func caseInsensitiveModified() {
        let left = parse("Api_Key=abc")
        let right = parse("API_KEY=xyz")
        let options = DiffEngine.Options(caseInsensitiveKeys: true)
        let results = DiffEngine.diff(left: left, right: right, options: options)

        #expect(results.count == 1)
        #expect(results[0].category == .modified)
    }

    // MARK: - Export Prefix Handling

    @Test("Export preserve mode: export and non-export are same key")
    func exportPreserve() {
        // EnvParser strips 'export ' from the key, so the key is the same
        let left = parse("export DB_HOST=localhost")
        let right = parse("DB_HOST=localhost")
        let results = DiffEngine.diff(left: left, right: right, options: DiffEngine.Options(exportMode: .preserve))

        #expect(results.count == 1)
        #expect(results[0].category == .equal)
    }

    @Test("Export remove mode: same matching as preserve since parser strips export")
    func exportRemove() {
        let left = parse("export API_KEY=abc")
        let right = parse("API_KEY=abc")
        let options = DiffEngine.Options(exportMode: .remove)
        let results = DiffEngine.diff(left: left, right: right, options: options)

        #expect(results.count == 1)
        #expect(results[0].category == .equal)
    }

    @Test("Export skip mode: excludes export lines from diff")
    func exportSkip() {
        let left = parse("export API_KEY=abc\nDB_HOST=localhost")
        let right = parse("DB_HOST=localhost")
        let options = DiffEngine.Options(exportMode: .skip)
        let results = DiffEngine.diff(left: left, right: right, options: options)

        // export API_KEY is skipped, only DB_HOST remains
        #expect(results.count == 1)
        #expect(results[0].category == .equal)
        #expect(results[0].leftEntry?.key == "DB_HOST")
    }

    @Test("Export skip mode: excludes export lines from both sides")
    func exportSkipBothSides() {
        let left = parse("export A=1\nB=2")
        let right = parse("B=2\nexport C=3")
        let options = DiffEngine.Options(exportMode: .skip)
        let results = DiffEngine.diff(left: left, right: right, options: options)

        #expect(results.count == 1)
        #expect(results[0].category == .equal)
        #expect(results[0].leftEntry?.key == "B")
    }

    // MARK: - Whitespace Normalization

    @Test("Whitespace around = is normalized by parser")
    func whitespaceAroundEquals() {
        let left = parse("KEY = value")
        let right = parse("KEY=value")
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.count == 1)
        #expect(results[0].category == .equal)
    }

    @Test("Whitespace in value is normalized for comparison")
    func whitespaceInValue() {
        let left = parse("KEY=  value  ")
        let right = parse("KEY=value")
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.count == 1)
        #expect(results[0].category == .equal)
    }

    // MARK: - Comments and Blanks Excluded

    @Test("Comments are excluded from diff results")
    func commentsExcluded() {
        let left = parse("# comment\nKEY=value")
        let right = parse("# different comment\nKEY=value")
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.count == 1)
        #expect(results[0].category == .equal)
        #expect(results[0].leftEntry?.key == "KEY")
    }

    @Test("Blank lines are excluded from diff results")
    func blanksExcluded() {
        let left = parse("A=1\n\n\nB=2")
        let right = parse("A=1\nB=2")
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.category == .equal })
    }

    @Test("Malformed lines are excluded from diff results")
    func malformedExcluded() {
        let left = parse("KEY=value\nmalformed line")
        let right = parse("KEY=value")
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.count == 1)
        #expect(results[0].category == .equal)
    }

    // MARK: - Edge Cases

    @Test("Empty files produce empty results")
    func emptyFiles() {
        let left = parse("")
        let right = parse("")
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.isEmpty)
    }

    @Test("Left empty, right has entries")
    func leftEmpty() {
        let left = parse("")
        let right = parse("A=1\nB=2")
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.category == .rightOnly })
    }

    @Test("Right empty, left has entries")
    func rightEmpty() {
        let left = parse("A=1\nB=2")
        let right = parse("")
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.category == .leftOnly })
    }

    @Test("Files with only comments and blanks produce empty results")
    func onlyCommentsAndBlanks() {
        let left = parse("# comment\n\n# another")
        let right = parse("# different\n\n")
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.isEmpty)
    }

    @Test("Combined options: case-insensitive with export skip")
    func combinedOptions() {
        let left = parse("export api_key=secret\ndb_host=localhost")
        let right = parse("DB_HOST=localhost")
        let options = DiffEngine.Options(caseInsensitiveKeys: true, exportMode: .skip)
        let results = DiffEngine.diff(left: left, right: right, options: options)

        #expect(results.count == 1)
        #expect(results[0].category == .equal)
    }
}
