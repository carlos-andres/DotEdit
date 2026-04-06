import Foundation
import Testing
@testable import DotEdit

@Suite("ConsolidateEngine")
struct ConsolidateEngineTests {

    // MARK: - Helpers

    private func parse(_ content: String) -> EnvFile {
        EnvParser.parse(content: content, filePath: "test")
    }

    // MARK: - Basic Consolidate

    @Test("Groups, sorts, adds section headers")
    func basicConsolidate() {
        let file = parse("DB_PORT=5432\nAPI_KEY=abc\nDB_HOST=localhost\nAPI_URL=http")
        let keys = file.keyValueEntries.compactMap(\.key)
        let convention = NamingConvention.detectDominant(keys: keys).dominant

        let result = ConsolidateEngine.consolidate(entries: file.entries, convention: convention)

        // Should have: header + API_KEY + API_URL + blank + header + DB_HOST + DB_PORT
        #expect(result.groupCount == 2)
        #expect(result.keyCount == 4)

        // Check group headers exist
        let headers = result.lines.filter { $0.hasPrefix("# ===") }
        #expect(headers.count == 2)

        // Check alphabetical order within groups
        let apiIdx = result.lines.firstIndex { $0.contains("API_KEY") }!
        let apiUrlIdx = result.lines.firstIndex { $0.contains("API_URL") }!
        #expect(apiIdx < apiUrlIdx)

        let dbHostIdx = result.lines.firstIndex { $0.contains("DB_HOST") }!
        let dbPortIdx = result.lines.firstIndex { $0.contains("DB_PORT") }!
        #expect(dbHostIdx < dbPortIdx)
    }

    // MARK: - Strips Comments

    @Test("Removes standalone comments, keeps section headers")
    func stripsComments() {
        let file = parse("# Database settings\nDB_HOST=localhost\n# API config\nAPI_KEY=abc")
        let keys = file.keyValueEntries.compactMap(\.key)
        let convention = NamingConvention.detectDominant(keys: keys).dominant

        let result = ConsolidateEngine.consolidate(entries: file.entries, convention: convention)

        // Original comments should be stripped
        let originalComments = result.lines.filter { $0 == "# Database settings" || $0 == "# API config" }
        #expect(originalComments.isEmpty)

        // Section headers should exist
        let headers = result.lines.filter { $0.hasPrefix("# ===") }
        #expect(headers.count >= 1)
    }

    // MARK: - Strips Blank Lines

    @Test("Replaces with structured single blank between groups")
    func stripsBlankLines() {
        let file = parse("DB_HOST=localhost\n\n\n\nAPI_KEY=abc")
        let keys = file.keyValueEntries.compactMap(\.key)
        let convention = NamingConvention.detectDominant(keys: keys).dominant

        let result = ConsolidateEngine.consolidate(entries: file.entries, convention: convention)

        // No consecutive blank lines
        for i in 0..<result.lines.count - 1 {
            let bothBlank = result.lines[i].isEmpty && result.lines[i + 1].isEmpty
            #expect(!bothBlank, "Consecutive blank lines at index \(i)")
        }
    }

    // MARK: - Preserves Values

    @Test("rawLine preserved exactly (quotes, export prefix)")
    func preservesValues() {
        let file = parse("export DB_HOST=\"localhost\"\nAPI_KEY='secret value'")
        let keys = file.keyValueEntries.compactMap(\.key)
        let convention = NamingConvention.detectDominant(keys: keys).dominant

        let result = ConsolidateEngine.consolidate(entries: file.entries, convention: convention)

        #expect(result.lines.contains("export DB_HOST=\"localhost\""))
        #expect(result.lines.contains("API_KEY='secret value'"))
    }

    // MARK: - OTHER Group

    @Test("Non-conforming keys in OTHER section")
    func otherGroup() {
        let file = parse("DB_HOST=localhost\napp.url=http\nAPI_KEY=abc")
        let keys = file.keyValueEntries.compactMap(\.key)
        let convention = NamingConvention.detectDominant(keys: keys).dominant

        let result = ConsolidateEngine.consolidate(entries: file.entries, convention: convention)

        // dot.notation key should be in OTHER group
        let otherHeader = result.lines.contains("# === OTHER ===")
        #expect(otherHeader)
    }

    // MARK: - Reports Counts

    @Test("Correct groupCount and keyCount")
    func reportsCounts() {
        let file = parse("DB_HOST=localhost\nDB_PORT=5432\nAPI_KEY=abc\nCACHE_TTL=300")
        let keys = file.keyValueEntries.compactMap(\.key)
        let convention = NamingConvention.detectDominant(keys: keys).dominant

        let result = ConsolidateEngine.consolidate(entries: file.entries, convention: convention)

        #expect(result.keyCount == 4)
        #expect(result.groupCount == 3) // API, CACHE, DB
    }
}
