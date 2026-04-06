import Foundation
import Testing
@testable import DotEdit

@Suite("Sequential Diff")
struct SequentialDiffTests {

    // MARK: - Helpers

    private func parse(_ content: String) -> EnvFile {
        EnvParser.parse(content: content, filePath: "test")
    }

    private func sequentialOptions() -> DiffEngine.Options {
        DiffEngine.Options(diffMode: .sequential)
    }

    // MARK: - Tests

    @Test("Position-based comparison")
    func positionBased() {
        let left = parse("A=1\nB=2\nC=3")
        let right = parse("A=1\nB=changed\nC=3")
        let results = DiffEngine.diff(left: left, right: right, options: sequentialOptions())

        #expect(results.count == 3)
        #expect(results[0].category == .equal)
        #expect(results[1].category == .modified)
        #expect(results[2].category == .equal)
    }

    @Test("Includes comments as diff entries")
    func includesComments() {
        let left = parse("# comment\nA=1")
        let right = parse("# comment\nA=1")
        let results = DiffEngine.diff(left: left, right: right, options: sequentialOptions())

        #expect(results.count == 2)
        #expect(results[0].category == .equal)
        #expect(results[0].leftEntry?.type == .comment)
    }

    @Test("Different comments are modified")
    func differentComments() {
        let left = parse("# dev\nA=1")
        let right = parse("# prod\nA=1")
        let results = DiffEngine.diff(left: left, right: right, options: sequentialOptions())

        #expect(results[0].category == .modified)
        #expect(results[1].category == .equal)
    }

    @Test("Left longer — extras are leftOnly")
    func leftLonger() {
        let left = parse("A=1\nB=2\nC=3")
        let right = parse("A=1")
        let results = DiffEngine.diff(left: left, right: right, options: sequentialOptions())

        #expect(results.count == 3)
        #expect(results[0].category == .equal)
        #expect(results[1].category == .leftOnly)
        #expect(results[2].category == .leftOnly)
    }

    @Test("Right longer — extras are rightOnly")
    func rightLonger() {
        let left = parse("A=1")
        let right = parse("A=1\nB=2\nC=3")
        let results = DiffEngine.diff(left: left, right: right, options: sequentialOptions())

        #expect(results.count == 3)
        #expect(results[0].category == .equal)
        #expect(results[1].category == .rightOnly)
        #expect(results[2].category == .rightOnly)
    }

    @Test("Case-insensitive in sequential mode")
    func caseInsensitive() {
        let left = parse("APP_KEY=sample")
        let right = parse("app_key=sample")
        var opts = sequentialOptions()
        opts.caseInsensitiveKeys = true
        let results = DiffEngine.diff(left: left, right: right, options: opts)

        #expect(results.count == 1)
        #expect(results[0].category == .equal)
    }

    // MARK: - DEC-042: Clean State on Load

    @Test("resetComparisonState clears sequential and case-insensitive")
    func resetComparisonState() {
        let testDefaults = UserDefaults(suiteName: "test.resetState")!
        testDefaults.removePersistentDomain(forName: "test.resetState")
        let settings = AppSettings(defaults: testDefaults)

        // Enable both session toggles
        settings.sequentialDiff = true
        settings.caseInsensitiveKeys = true
        #expect(settings.sequentialDiff == true)
        #expect(settings.caseInsensitiveKeys == true)

        // Reset
        settings.resetComparisonState()
        #expect(settings.sequentialDiff == false)
        #expect(settings.caseInsensitiveKeys == false)

        // Verify UserDefaults also cleared
        #expect(testDefaults.bool(forKey: "settings.sequentialDiff") == false)
        #expect(testDefaults.bool(forKey: "settings.caseInsensitiveKeys") == false)
    }

    @Test("resetComparisonState preserves Tier 1 settings")
    func resetPreservesTier1() {
        let testDefaults = UserDefaults(suiteName: "test.resetPreserve")!
        testDefaults.removePersistentDomain(forName: "test.resetPreserve")
        let settings = AppSettings(defaults: testDefaults)

        // Set Tier 1 settings
        settings.fontSize = 16
        settings.createBackupOnSave = false
        settings.wordWrap = true
        settings.sequentialDiff = true

        // Reset — only Tier 2 should change
        settings.resetComparisonState()
        #expect(settings.sequentialDiff == false)
        #expect(settings.fontSize == 16)
        #expect(settings.createBackupOnSave == false)
        #expect(settings.wordWrap == true)
    }

    @Test("Key-based default unchanged")
    func keyBasedUnchanged() {
        let left = parse("B=2\nA=1")
        let right = parse("A=1\nB=2")
        // Default key-based mode: matches by key, order doesn't matter
        let results = DiffEngine.diff(left: left, right: right)

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.category == .equal })
    }

    // MARK: - EC-012: Switching diff mode mid-session

    @Test("Switch diff mode mid-session: key-based → sequential → key-based (EC-012)")
    @MainActor func switchDiffModeMidSession() {
        let testDefaults = UserDefaults(suiteName: "test.ec012.switchMode")!
        testDefaults.removePersistentDomain(forName: "test.ec012.switchMode")
        let settings = AppSettings(defaults: testDefaults)

        // Files where key order differs — key-based matches by key, sequential by position
        let leftFile = EnvParser.parse(content: "B=2\nA=1\nC=3", filePath: "left")
        let rightFile = EnvParser.parse(content: "A=1\nB=2\nD=4", filePath: "right")

        let vm = ComparisonViewModel(leftFile: leftFile, rightFile: rightFile, settings: settings)

        // --- Phase 1: Key-based (default) ---
        #expect(settings.sequentialDiff == false)
        let keyBasedRows = vm.rows
        let keyBasedCategories = keyBasedRows.map(\.diffCategory)

        // Key-based: A=1 matches A=1 (equal), B=2 matches B=2 (equal), C=3 leftOnly, D=4 rightOnly
        let keyBasedEqual = keyBasedCategories.filter { $0 == .equal }.count
        let keyBasedLeftOnly = keyBasedCategories.filter { $0 == .leftOnly }.count
        let keyBasedRightOnly = keyBasedCategories.filter { $0 == .rightOnly }.count
        #expect(keyBasedEqual == 2, "Key-based should match A and B as equal")
        #expect(keyBasedLeftOnly == 1, "Key-based should have C as leftOnly")
        #expect(keyBasedRightOnly == 1, "Key-based should have D as rightOnly")

        // --- Phase 2: Toggle to sequential ---
        settings.sequentialDiff = true
        vm.reDiff()

        let seqRows = vm.rows
        let seqCategories = seqRows.map(\.diffCategory)

        // Sequential (position-based): B=2 vs A=1 (modified), A=1 vs B=2 (modified), C=3 vs D=4 (modified)
        #expect(seqRows.count == 3, "Sequential should have exactly 3 positional rows")
        let seqModified = seqCategories.filter { $0 == .modified }.count
        #expect(seqModified == 3, "Sequential: all 3 positions have different values")

        // Verify structure changed from key-based
        #expect(seqCategories != keyBasedCategories, "Sequential categories should differ from key-based")

        // --- Phase 3: Toggle back to key-based ---
        settings.sequentialDiff = false
        vm.reDiff()

        let restoredRows = vm.rows
        let restoredCategories = restoredRows.map(\.diffCategory)

        // Should match original key-based results exactly
        let restoredEqual = restoredCategories.filter { $0 == .equal }.count
        let restoredLeftOnly = restoredCategories.filter { $0 == .leftOnly }.count
        let restoredRightOnly = restoredCategories.filter { $0 == .rightOnly }.count
        #expect(restoredEqual == keyBasedEqual, "Restored key-based should have same equal count")
        #expect(restoredLeftOnly == keyBasedLeftOnly, "Restored key-based should have same leftOnly count")
        #expect(restoredRightOnly == keyBasedRightOnly, "Restored key-based should have same rightOnly count")
    }
}
