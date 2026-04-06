import Foundation
import Testing
@testable import DotEdit

@Suite("SemanticReorg")
struct SemanticReorgTests {

    // MARK: - Helpers

    private func parse(_ content: String) -> EnvFile {
        EnvParser.parse(content: content, filePath: "test")
    }

    // MARK: - Basic Grouping

    @Test("Groups entries by prefix with headers")
    func basicGrouping() {
        let file = parse("DB_HOST=localhost\nDB_PORT=5432\nAPI_KEY=abc\nAPI_URL=https://api.com")
        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .screamingSnake
        )

        #expect(result.groupCount == 2)
        #expect(result.keyCount == 4)

        // API group comes before DB (alphabetical)
        #expect(result.lines.contains("# === API ==="))
        #expect(result.lines.contains("# === DB ==="))

        // Verify ordering: API group first
        let apiIdx = result.lines.firstIndex(of: "# === API ===")!
        let dbIdx = result.lines.firstIndex(of: "# === DB ===")!
        #expect(apiIdx < dbIdx)
    }

    @Test("Sorts keys alphabetically within groups")
    func sortedWithinGroups() {
        let file = parse("DB_PORT=5432\nDB_HOST=localhost\nDB_NAME=mydb")
        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .screamingSnake
        )

        let dbHeader = result.lines.firstIndex(of: "# === DB ===")!
        let hostIdx = result.lines.firstIndex(of: "DB_HOST=localhost")!
        let nameIdx = result.lines.firstIndex(of: "DB_NAME=mydb")!
        let portIdx = result.lines.firstIndex(of: "DB_PORT=5432")!

        #expect(hostIdx > dbHeader)
        #expect(nameIdx > hostIdx)
        #expect(portIdx > nameIdx)
    }

    @Test("Non-conforming keys go to OTHER group")
    func otherGroup() {
        let file = parse("DB_HOST=localhost\napp.url=http://localhost")
        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .screamingSnake
        )

        #expect(result.lines.contains("# === DB ==="))
        #expect(result.lines.contains("# === OTHER ==="))
        #expect(result.groupCount == 2)
    }

    @Test("Blank line separators between groups")
    func blankLineSeparators() {
        let file = parse("DB_HOST=localhost\nAPI_KEY=abc")
        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .screamingSnake
        )

        // Should have blank line between groups
        let apiIdx = result.lines.firstIndex(of: "# === API ===")!
        let dbIdx = result.lines.firstIndex(of: "# === DB ===")!

        // Blank line exists between the groups
        let blankIdx = result.lines.firstIndex(of: "")
        #expect(blankIdx != nil)
        #expect(blankIdx! > apiIdx && blankIdx! < dbIdx)
    }

    // MARK: - Comment Handling

    @Test("moveWithKey attaches comments to following key")
    func commentsMoveWithKey() {
        let file = parse("# Database config\nDB_HOST=localhost\nDB_PORT=5432")
        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .screamingSnake,
            commentHandling: .moveWithKey
        )

        // Comment should appear before DB_HOST
        let commentIdx = result.lines.firstIndex(of: "# Database config")!
        let hostIdx = result.lines.firstIndex(of: "DB_HOST=localhost")!
        #expect(commentIdx == hostIdx - 1)
    }

    @Test("moveToEnd collects comments at end")
    func commentsMoveToEnd() {
        let file = parse("# Database config\nDB_HOST=localhost\nAPI_KEY=abc")
        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .screamingSnake,
            commentHandling: .moveToEnd
        )

        #expect(result.lines.contains("# === COMMENTS ==="))
        // Comment should be after all key groups
        let commentsHeader = result.lines.firstIndex(of: "# === COMMENTS ===")!
        let lastKeyGroupHeader = max(
            result.lines.firstIndex(of: "# === API ===")!,
            result.lines.firstIndex(of: "# === DB ===")!
        )
        #expect(commentsHeader > lastKeyGroupHeader)
    }

    @Test("discard removes comments entirely")
    func commentsDiscard() {
        let file = parse("# Database config\nDB_HOST=localhost\nAPI_KEY=abc")
        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .screamingSnake,
            commentHandling: .discard
        )

        #expect(!result.lines.contains("# Database config"))
        #expect(!result.lines.contains("# === COMMENTS ==="))
    }

    @Test("Orphan comments (no following key) go to end")
    func orphanComments() {
        let file = parse("DB_HOST=localhost\n\n# This is orphaned")
        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .screamingSnake,
            commentHandling: .moveWithKey
        )

        // Orphan comment should appear at the end
        let orphanIdx = result.lines.firstIndex(of: "# This is orphaned")!
        let dbIdx = result.lines.firstIndex(of: "DB_HOST=localhost")!
        #expect(orphanIdx > dbIdx)
    }

    // MARK: - Edge Cases

    @Test("Empty entries returns empty result")
    func emptyEntries() {
        let file = parse("")
        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .screamingSnake
        )

        #expect(result.groupCount == 0)
        #expect(result.keyCount == 0)
    }

    @Test("Single key produces single group")
    func singleKey() {
        let file = parse("DB_HOST=localhost")
        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .screamingSnake
        )

        #expect(result.groupCount == 1)
        #expect(result.keyCount == 1)
        #expect(result.lines.contains("# === DB ==="))
    }

    @Test("All same prefix produces single group")
    func samePrefix() {
        let file = parse("DB_HOST=localhost\nDB_PORT=5432\nDB_NAME=mydb")
        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .screamingSnake
        )

        #expect(result.groupCount == 1)
        #expect(result.keyCount == 3)
        // No blank separator when only one group
        #expect(result.lines.first == "# === DB ===")
    }

    @Test("Dot notation grouping")
    func dotNotationGrouping() {
        let file = parse("app.url=http://localhost\napp.name=MyApp\ndb.host=localhost")
        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .dotNotation
        )

        #expect(result.groupCount == 2)
        #expect(result.lines.contains("# === APP ==="))
        #expect(result.lines.contains("# === DB ==="))
    }

    @Test("Kebab case grouping")
    func kebabCaseGrouping() {
        let file = parse("api-key=abc\napi-url=http://api\ndb-host=localhost")
        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .kebabCase
        )

        #expect(result.groupCount == 2)
        #expect(result.lines.contains("# === API ==="))
        #expect(result.lines.contains("# === DB ==="))
    }

    @Test("Keys without prefix delimiter stay as full key group")
    func noDelimiterKeys() {
        let file = parse("PORT=3000\nHOST=localhost")
        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .screamingSnake
        )

        // Each key IS its own prefix since no underscore
        #expect(result.groupCount == 2)
        #expect(result.lines.contains("# === HOST ==="))
        #expect(result.lines.contains("# === PORT ==="))
    }
}
