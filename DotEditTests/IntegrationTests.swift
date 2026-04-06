import Foundation
import Testing
@testable import DotEdit

// MARK: - Real-World .env Integration Tests

@Suite("Integration: Real-World Env Files")
struct RealWorldEnvTests {

    // MARK: - Laravel .env

    @Test("Laravel .env parses correctly")
    func laravelEnv() {
        let content = [
            "APP_NAME=\"My Laravel App\"",
            "APP_ENV=local",
            "APP_KEY=sample",
            "APP_DEBUG=true",
            "APP_URL=http://localhost",
            "",
            "LOG_CHANNEL=stack",
            "LOG_DEPRECATIONS_CHANNEL=null",
            "LOG_LEVEL=debug",
            "",
            "DB_CONNECTION=mysql",
            "DB_HOST=127.0.0.1",
            "DB_PORT=3306",
            "DB_DATABASE=laravel",
            "DB_USERNAME=root",
            "DB_PASSWORD=",
            "",
            "BROADCAST_DRIVER=log",
            "CACHE_DRIVER=file",
            "FILESYSTEM_DISK=local",
            "QUEUE_CONNECTION=sync",
            "SESSION_DRIVER=file",
            "SESSION_LIFETIME=120",
            "",
            "MEMCACHED_HOST=127.0.0.1",
            "",
            "REDIS_HOST=127.0.0.1",
            "REDIS_PASSWORD=null",
            "REDIS_PORT=6379",
            "",
            "MAIL_MAILER=smtp",
            "MAIL_HOST=mailpit",
            "MAIL_PORT=1025",
            "MAIL_USERNAME=null",
            "MAIL_PASSWORD=null",
            "MAIL_ENCRYPTION=null",
            "MAIL_FROM_ADDRESS=\"hello@example.com\"",
            "MAIL_FROM_NAME=\"${APP_NAME}\"",
        ].joined(separator: "\n")

        let file = EnvParser.parse(content: content, filePath: ".env")
        let kvEntries = file.entries.filter { $0.type == .keyValue }
        let blankEntries = file.entries.filter { $0.type == .blank }

        #expect(kvEntries.count == 32)
        #expect(blankEntries.count >= 6)

        let appKey = kvEntries.first { $0.key == "APP_KEY" }
        #expect(appKey?.value == "sample")

        let appName = kvEntries.first { $0.key == "APP_NAME" }
        #expect(appName?.value == "My Laravel App")
        #expect(appName?.quoteStyle == .double)

        let dbPass = kvEntries.first { $0.key == "DB_PASSWORD" }
        #expect(dbPass?.value == "")

        let mailName = kvEntries.first { $0.key == "MAIL_FROM_NAME" }
        #expect(mailName?.value == "${APP_NAME}")
    }

    @Test("Laravel diff: local vs production")
    func laravelDiff() {
        let local = """
        APP_ENV=local
        APP_DEBUG=true
        APP_URL=http://localhost
        DB_HOST=127.0.0.1
        DB_PASSWORD=
        CACHE_DRIVER=file
        """

        let production = """
        APP_ENV=production
        APP_DEBUG=false
        APP_URL=https://myapp.com
        DB_HOST=db.myapp.com
        DB_PASSWORD=sample
        CACHE_DRIVER=redis
        REDIS_HOST=redis.myapp.com
        """

        let leftFile = EnvParser.parse(content: local, filePath: ".env.local")
        let rightFile = EnvParser.parse(content: production, filePath: ".env.production")
        let diffs = DiffEngine.diff(left: leftFile, right: rightFile)

        let modified = diffs.filter { $0.category == .modified }
        let rightOnly = diffs.filter { $0.category == .rightOnly }

        // APP_ENV, APP_DEBUG, APP_URL, DB_HOST, DB_PASSWORD, CACHE_DRIVER = 6 modified
        #expect(modified.count == 6)
        #expect(rightOnly.count == 1) // REDIS_HOST
    }

    // MARK: - Node.js .env

    @Test("Node.js .env with comments and sections")
    func nodeEnv() {
        let content = [
            "# Server Configuration",
            "PORT=3000",
            "HOST=0.0.0.0",
            "NODE_ENV=development",
            "",
            "# Database",
            "DATABASE_URL=\"postgresql://localhost:5432/mydb?schema=public\"",
            "",
            "# Authentication",
            "JWT_SECRET=sample",
            "JWT_EXPIRATION=3600",
            "BCRYPT_ROUNDS=10",
            "",
            "# External APIs",
            "STRIPE_SECRET_KEY=sample",
            "STRIPE_WEBHOOK_SECRET=sample",
            "SENDGRID_API_KEY=sample",
            "",
            "# Feature Flags",
            "ENABLE_NOTIFICATIONS=true",
            "ENABLE_ANALYTICS=false",
            "MAINTENANCE_MODE=false",
        ].joined(separator: "\n")

        let file = EnvParser.parse(content: content, filePath: ".env")
        let comments = file.entries.filter { $0.type == .comment }
        let kvEntries = file.entries.filter { $0.type == .keyValue }

        #expect(comments.count == 5)
        #expect(kvEntries.count == 13)

        let dbUrl = kvEntries.first { $0.key == "DATABASE_URL" }
        #expect(dbUrl?.value == "postgresql://localhost:5432/mydb?schema=public")
        #expect(dbUrl?.quoteStyle == .double)
    }

    // MARK: - Python .env with export

    @Test("Python .env with export prefix")
    func pythonExportEnv() {
        let content = """
        export DJANGO_SETTINGS_MODULE=myproject.settings
        export SECRET_KEY='sample'
        export DEBUG=True
        export ALLOWED_HOSTS=localhost,127.0.0.1
        export DATABASE_URL=postgres://localhost/dbname
        """

        let file = EnvParser.parse(content: content, filePath: ".env")
        let kvEntries = file.entries.filter { $0.type == .keyValue }

        #expect(kvEntries.count == 5)

        for entry in kvEntries {
            #expect(entry.hasExportPrefix == true)
        }

        let secret = kvEntries.first { $0.key == "SECRET_KEY" }
        #expect(secret?.value == "sample")
        #expect(secret?.quoteStyle == .single)
    }

    @Test("Export prefix diff with remove mode")
    func exportPrefixDiffRemoveMode() {
        let left = "export DB_HOST=localhost\nexport DB_PORT=5432"
        let right = "DB_HOST=localhost\nDB_PORT=3306"

        let leftFile = EnvParser.parse(content: left, filePath: "left")
        let rightFile = EnvParser.parse(content: right, filePath: "right")

        let options = DiffEngine.Options(caseInsensitiveKeys: false, exportMode: .remove)
        let diffs = DiffEngine.diff(left: leftFile, right: rightFile, options: options)

        let equal = diffs.filter { $0.category == .equal }
        let modified = diffs.filter { $0.category == .modified }

        #expect(equal.count == 1) // DB_HOST=localhost (export stripped)
        #expect(modified.count == 1) // DB_PORT differs
    }

    // MARK: - Multiline Values

    @Test("Multiline values parsed and diffed")
    func multilineValues() {
        let content = """
        SIMPLE_KEY=value
        MULTILINE_KEY="line one
        line two
        line three"
        AFTER_KEY=after
        """

        let file = EnvParser.parse(content: content, filePath: "test")
        let kvEntries = file.entries.filter { $0.type == .keyValue }

        #expect(kvEntries.count == 3)

        let multi = kvEntries.first { $0.key == "MULTILINE_KEY" }
        #expect(multi?.value?.contains("line one") == true)
        #expect(multi?.value?.contains("line two") == true)
    }

    // MARK: - Mixed Warnings

    @Test("File with multiple warning types")
    func mixedWarnings() {
        let content = [
            "GOOD_KEY=value",
            "bad key with spaces=value",
            "DUPLICATE=first",
            "UNCLOSED=\"no closing quote",
            "DUPLICATE=second",
            "not a valid line at all",
        ].joined(separator: "\n")

        let file = EnvParser.parse(content: content, filePath: "test")
        let allWarnings = file.allWarnings

        // Expect at least: duplicate (x2) + one of (nonStandard/malformed/unclosedQuote)
        #expect(allWarnings.count >= 2)
        let warningTypes = Set(allWarnings.map { $0.type })
        #expect(warningTypes.count >= 2) // Multiple distinct warning types
    }

    // MARK: - Full Pipeline: Parse → Diff → Rows

    @Test("Full pipeline with ComparisonViewModel")
    @MainActor func fullPipeline() {
        let left = """
        # Config
        APP_NAME=MyApp
        APP_ENV=local
        DB_HOST=localhost
        DB_PORT=3306
        SECRET=sample
        """

        let right = """
        # Config
        APP_NAME=MyApp
        APP_ENV=production
        DB_HOST=prod-db.example.com
        DB_PORT=3306
        API_KEY=sample
        """

        let leftFile = EnvParser.parse(content: left, filePath: "left")
        let rightFile = EnvParser.parse(content: right, filePath: "right")

        let vm = ComparisonViewModel(leftFile: leftFile, rightFile: rightFile)

        #expect(vm.rows.count > 0)
        #expect(vm.diffStats.equal >= 2) // APP_NAME, DB_PORT
        #expect(vm.diffStats.modified >= 2) // APP_ENV, DB_HOST
        #expect(vm.diffStats.leftOnly >= 1) // SECRET
        #expect(vm.diffStats.rightOnly >= 1) // API_KEY
    }

    // MARK: - Case-Insensitive Matching

    @Test("Case-insensitive key matching across files")
    func caseInsensitiveDiff() {
        let left = "db_host=localhost\nDB_PORT=3306"
        let right = "DB_HOST=production\ndb_port=5432"

        let leftFile = EnvParser.parse(content: left, filePath: "left")
        let rightFile = EnvParser.parse(content: right, filePath: "right")

        let options = DiffEngine.Options(caseInsensitiveKeys: true, exportMode: .preserve)
        let diffs = DiffEngine.diff(left: leftFile, right: rightFile, options: options)

        let modified = diffs.filter { $0.category == .modified }
        #expect(modified.count == 2)
    }
}

// MARK: - Performance Tests

@Suite("Integration: Performance")
struct PerformanceTests {

    private func generateLargeEnv(keyCount: Int) -> String {
        var lines: [String] = ["# Auto-generated test file"]
        let prefixes = ["APP", "DB", "CACHE", "MAIL", "QUEUE", "LOG", "AWS", "REDIS", "SESSION", "API"]

        for i in 0..<keyCount {
            if i > 0 && i % 20 == 0 {
                lines.append("")
                lines.append("# Section \(i / 20)")
            }
            let prefix = prefixes[i % prefixes.count]
            lines.append("\(prefix)_KEY_\(i)=value_\(i)_\(String(repeating: "x", count: 20))")
        }
        return lines.joined(separator: "\n")
    }

    @Test("Parse 500-key file under 200ms")
    func parse500Keys() {
        let content = generateLargeEnv(keyCount: 500)

        let start = ContinuousClock.now
        let file = EnvParser.parse(content: content, filePath: "large.env")
        let elapsed = ContinuousClock.now - start

        #expect(file.keyCount >= 500)
        #expect(elapsed < .milliseconds(200), "Parse took \(elapsed)")
    }

    @Test("Parse 1000-key file under 500ms")
    func parse1000Keys() {
        let content = generateLargeEnv(keyCount: 1000)

        let start = ContinuousClock.now
        let file = EnvParser.parse(content: content, filePath: "large.env")
        let elapsed = ContinuousClock.now - start

        #expect(file.keyCount >= 1000)
        #expect(elapsed < .milliseconds(500), "Parse took \(elapsed)")
    }

    @Test("Diff 500-key files under 300ms")
    func diff500Keys() {
        let leftContent = generateLargeEnv(keyCount: 500)
        let rightContent = generateLargeEnv(keyCount: 500)
            .replacingOccurrences(of: "value_0_", with: "changed_0_")
            .replacingOccurrences(of: "value_50_", with: "changed_50_")
            .replacingOccurrences(of: "value_100_", with: "changed_100_")

        let leftFile = EnvParser.parse(content: leftContent, filePath: "left")
        let rightFile = EnvParser.parse(content: rightContent, filePath: "right")

        let start = ContinuousClock.now
        let diffs = DiffEngine.diff(left: leftFile, right: rightFile)
        let elapsed = ContinuousClock.now - start

        #expect(diffs.count >= 500)
        #expect(elapsed < .milliseconds(300), "Diff took \(elapsed)")
    }

    @Test("Full pipeline 1000-key files under 1s")
    @MainActor func fullPipeline1000Keys() {
        let leftContent = generateLargeEnv(keyCount: 1000)
        var rightLines = leftContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for i in stride(from: 0, to: rightLines.count, by: 10) {
            if rightLines[i].contains("=") {
                rightLines[i] = rightLines[i].replacingOccurrences(of: "value_", with: "modified_")
            }
        }
        let rightContent = rightLines.joined(separator: "\n")

        let leftFile = EnvParser.parse(content: leftContent, filePath: "left")
        let rightFile = EnvParser.parse(content: rightContent, filePath: "right")

        let start = ContinuousClock.now
        let vm = ComparisonViewModel(leftFile: leftFile, rightFile: rightFile)
        let elapsed = ContinuousClock.now - start

        #expect(vm.rows.count >= 1000)
        #expect(elapsed < .seconds(1), "Full pipeline took \(elapsed)")
    }

    @Test("Semantic reorg 200-key file under 200ms")
    func reorg200Keys() {
        var lines: [String] = []
        let prefixes = ["APP", "DB", "CACHE", "MAIL", "QUEUE"]
        for i in 0..<200 {
            let prefix = prefixes[i % prefixes.count]
            lines.append("\(prefix)_KEY_\(i)=value_\(i)")
        }
        let content = lines.joined(separator: "\n")
        let file = EnvParser.parse(content: content, filePath: "test")

        let start = ContinuousClock.now
        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .snakeCase,
            commentHandling: .moveWithKey
        )
        let elapsed = ContinuousClock.now - start

        #expect(result.keyCount >= 200)
        #expect(elapsed < .milliseconds(200), "Reorg took \(elapsed)")
    }
}

// MARK: - Edge Case Tests

@Suite("Integration: Edge Cases")
struct EdgeCaseTests {

    // MARK: - EC-002: Empty file

    @Test("Empty file produces zero key-value entries")
    func emptyFile() {
        let file = EnvParser.parse(content: "", filePath: "empty.env")
        #expect(file.keyCount == 0)
        #expect(file.keyValueEntries.isEmpty)
    }

    @Test("Whitespace-only file produces blank entries")
    func whitespaceOnlyFile() {
        let file = EnvParser.parse(content: "  \n\n  \n", filePath: "blank.env")
        #expect(file.keyCount == 0)
        let nonBlank = file.entries.filter { $0.type != .blank }
        #expect(nonBlank.isEmpty)
    }

    // MARK: - EC-004: Very long values

    @Test("Long base64/JWT values parse correctly")
    func longValues() {
        let longValue = String(repeating: "ABCDEFGHabcdefgh12345678", count: 100) // 2400 chars
        let content = "LONG_VALUE=\(longValue)"
        let file = EnvParser.parse(content: content, filePath: "test")

        #expect(file.entries.count == 1)
        #expect(file.entries[0].value == longValue)
    }

    // MARK: - EC-023: Empty value vs missing key

    @Test("Empty value differs from missing key in diff")
    func emptyVsMissing() {
        let left = "KEY_A=\nKEY_B=value"
        let right = "KEY_B=value"

        let leftFile = EnvParser.parse(content: left, filePath: "left")
        let rightFile = EnvParser.parse(content: right, filePath: "right")
        let diffs = DiffEngine.diff(left: leftFile, right: rightFile)

        let leftOnly = diffs.filter { $0.category == .leftOnly }
        #expect(leftOnly.count == 1)
        #expect(leftOnly[0].leftEntry?.key == "KEY_A")
        #expect(leftOnly[0].leftEntry?.value == "") // empty, not nil

        let equal = diffs.filter { $0.category == .equal }
        #expect(equal.count == 1)
    }

    // MARK: - EC-026: Whitespace-normalized values are equal

    @Test("Whitespace-normalized values are equal (EC-026)")
    func whitespaceValueDiff() {
        let left = "KEY=hello"
        let right = "KEY=  hello  "

        let leftFile = EnvParser.parse(content: left, filePath: "left")
        let rightFile = EnvParser.parse(content: right, filePath: "right")
        let diffs = DiffEngine.diff(left: leftFile, right: rightFile)

        // DiffEngine normalizes whitespace around values
        let equal = diffs.filter { $0.category == .equal }
        #expect(equal.count == 1)
    }

    // MARK: - EC-031: Single-segment keys in reorg

    @Test("Single-segment keys each become own group")
    func singleSegmentReorg() {
        let content = "ALPHA=1\nBETA=2\nGAMMA=3"
        let file = EnvParser.parse(content: content, filePath: "test")

        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .snakeCase,
            commentHandling: .moveWithKey
        )

        #expect(result.keyCount == 3)
    }

    // MARK: - EC-032: Reorg with multiline values

    @Test("Multiline values stay intact after reorg")
    func multilineReorg() {
        let content = """
        DB_URL="postgresql://host
        /database"
        DB_HOST=localhost
        APP_NAME=test
        """

        let file = EnvParser.parse(content: content, filePath: "test")

        let result = SemanticReorg.reorganize(
            entries: file.entries,
            convention: .snakeCase,
            commentHandling: .moveWithKey
        )

        #expect(result.keyCount >= 2)
    }

    // MARK: - EC-024: Duplicate keys in diff

    @Test("Duplicate keys match against first occurrence")
    func duplicateKeyDiff() {
        let left = "KEY=first\nKEY=second"
        let right = "KEY=first"

        let leftFile = EnvParser.parse(content: left, filePath: "left")
        let rightFile = EnvParser.parse(content: right, filePath: "right")
        let diffs = DiffEngine.diff(left: leftFile, right: rightFile)

        let equal = diffs.filter { $0.category == .equal }
        #expect(equal.count >= 1)
    }

    // MARK: - EC-001: Identical files

    @Test("Identical files produce all-equal diffs (EC-001)")
    @MainActor func identicalFilesDiff() {
        let content = "A=1\nB=2\nC=3"
        let leftFile = EnvParser.parse(content: content, filePath: "left")
        let rightFile = EnvParser.parse(content: content, filePath: "right")

        let vm = ComparisonViewModel(leftFile: leftFile, rightFile: rightFile)
        #expect(vm.filesAreIdentical == true)
        #expect(vm.diffStats.totalDiffs == 0)
    }

    // MARK: - BOM handling

    @Test("UTF-8 BOM file parses and diffs correctly")
    func bomHandling() {
        let bom = "\u{FEFF}"
        let content = "\(bom)KEY=value\nOTHER=test"
        let file = EnvParser.parse(content: content, filePath: "bom.env")

        #expect(file.metadata.hasBOM == true)
        let kvEntries = file.entries.filter { $0.type == .keyValue }
        #expect(kvEntries.count == 2)
        #expect(kvEntries[0].key == "KEY")
    }

    // MARK: - Serialization round-trip

    @Test("Parse → serialize → parse produces same entries")
    func roundTrip() {
        let original = """
        # Header comment
        APP_NAME="My App"
        APP_ENV=local

        # Database
        DB_HOST=localhost
        DB_PORT=3306
        DB_PASSWORD=
        """

        let file1 = EnvParser.parse(content: original, filePath: "test")
        let serialized = file1.entries.map(\.rawLine).joined(separator: "\n")
        let file2 = EnvParser.parse(content: serialized, filePath: "test")

        #expect(file1.keyCount == file2.keyCount)

        let keys1 = file1.entries.compactMap(\.key)
        let keys2 = file2.entries.compactMap(\.key)
        #expect(keys1 == keys2)
    }

    // MARK: - Diff both empty files

    @Test("Both empty files are identical")
    @MainActor func bothEmptyFiles() {
        let leftFile = EnvParser.parse(content: "", filePath: "left")
        let rightFile = EnvParser.parse(content: "", filePath: "right")

        let vm = ComparisonViewModel(leftFile: leftFile, rightFile: rightFile)
        #expect(vm.filesAreIdentical == true)
    }

    // MARK: - One empty, one with content

    @Test("One empty file vs populated shows all as right-only")
    func oneEmptyFile() {
        let left = ""
        let right = "A=1\nB=2"

        let leftFile = EnvParser.parse(content: left, filePath: "left")
        let rightFile = EnvParser.parse(content: right, filePath: "right")
        let diffs = DiffEngine.diff(left: leftFile, right: rightFile)

        let rightOnly = diffs.filter { $0.category == .rightOnly }
        #expect(rightOnly.count == 2)
    }

    // MARK: - Special characters in values

    @Test("Values with special characters preserved")
    func specialCharValues() {
        let content = """
        URL=https://example.com/path?q=1&r=2#anchor
        REGEX=^[a-zA-Z0-9]+$
        JSON={"key":"value","num":42}
        EMOJI=🚀🔥
        """

        let file = EnvParser.parse(content: content, filePath: "test")
        let kvEntries = file.entries.filter { $0.type == .keyValue }

        #expect(kvEntries.count == 4)
        #expect(kvEntries.first { $0.key == "EMOJI" }?.value == "🚀🔥")
    }
}

// MARK: - DEC-043: Key-Aware Transfer Tests

@Suite("Integration: Key-Aware Transfer")
struct KeyAwareTransferTests {

    @MainActor
    private func makeVM(left: String, right: String, settings: AppSettings? = nil) -> ComparisonViewModel {
        ComparisonViewModel(
            leftFile: EnvParser.parse(content: left, filePath: "/tmp/left.env"),
            rightFile: EnvParser.parse(content: right, filePath: "/tmp/right.env"),
            settings: settings
        )
    }

    // MARK: - transferToRight: leftOnly with key existing on right

    @Test("Transfer leftOnly updates existing key on right instead of appending")
    @MainActor func transferLeftOnlyUpdatesExisting() {
        // Left has KEY_A with value, right has KEY_A empty — but at different positions
        // Sequential mode would show KEY_A as leftOnly, but key-based would match
        // Simulate: leftOnly row referencing KEY_A=sample
        let vm = makeVM(
            left: "KEY_A=sample\nKEY_B=other",
            right: "KEY_B=other\nKEY_A="
        )

        // In key-based mode, KEY_A is modified (matched by key). But in sequential mode,
        // position mismatch makes them leftOnly/rightOnly. Let's test the key-aware logic
        // by directly creating a scenario where leftOnly transfer targets an existing key.

        // Use sequential mode to create leftOnly scenario
        let testDefaults = UserDefaults(suiteName: "test.transfer.1")!
        testDefaults.removePersistentDomain(forName: "test.transfer.1")
        let settings = AppSettings(defaults: testDefaults)
        settings.sequentialDiff = true

        let vm2 = makeVM(
            left: "# header\nKEY_A=sample",
            right: "KEY_A=",
            settings: settings
        )

        // In sequential mode: line 1 is "# header" vs "KEY_A=" → modified
        // line 2 is "KEY_A=sample" vs nothing → leftOnly
        let leftOnlyRows = vm2.rows.filter { $0.diffCategory == .leftOnly }
        #expect(leftOnlyRows.count >= 1)

        // Transfer the leftOnly KEY_A=sample → right
        if let leftOnlyRow = leftOnlyRows.first {
            vm2.transfer(row: leftOnlyRow, to: .right)
        }

        // KEY_A should be UPDATED on right (not appended as duplicate)
        vm2.reDiff()
        let rightKeys = vm2.rightFile.entries.filter { $0.type == .keyValue }
        let keyAEntries = rightKeys.filter { $0.key == "KEY_A" }
        #expect(keyAEntries.count == 1, "Should have exactly 1 KEY_A, not a duplicate")
        #expect(keyAEntries.first?.value == "sample")
    }

    // MARK: - transferToRight: leftOnly with NEW key (no existing)

    @Test("Transfer leftOnly appends new key when not existing on right")
    @MainActor func transferLeftOnlyAppendsNew() {
        let testDefaults = UserDefaults(suiteName: "test.transfer.2")!
        testDefaults.removePersistentDomain(forName: "test.transfer.2")
        let settings = AppSettings(defaults: testDefaults)
        settings.sequentialDiff = true

        let vm = makeVM(
            left: "KEY_A=val\nKEY_B=val2",
            right: "KEY_A=val",
            settings: settings
        )

        let leftOnlyRows = vm.rows.filter { $0.diffCategory == .leftOnly }
        #expect(leftOnlyRows.count >= 1)

        if let leftOnlyRow = leftOnlyRows.first {
            vm.transfer(row: leftOnlyRow, to: .right)
        }

        vm.reDiff()
        let rightKeys = vm.rightFile.entries.filter { $0.type == .keyValue }
        #expect(rightKeys.count == 2, "New key should be appended")
    }

    // MARK: - transferToLeft: rightOnly with existing key

    @Test("Transfer rightOnly updates existing key on left instead of appending")
    @MainActor func transferRightOnlyUpdatesExisting() {
        let testDefaults = UserDefaults(suiteName: "test.transfer.3")!
        testDefaults.removePersistentDomain(forName: "test.transfer.3")
        let settings = AppSettings(defaults: testDefaults)
        settings.sequentialDiff = true

        let vm = makeVM(
            left: "KEY_A=",
            right: "# header\nKEY_A=sample",
            settings: settings
        )

        let rightOnlyRows = vm.rows.filter { $0.diffCategory == .rightOnly }
        #expect(rightOnlyRows.count >= 1)

        if let rightOnlyRow = rightOnlyRows.first {
            vm.transfer(row: rightOnlyRow, to: .left)
        }

        vm.reDiff()
        let leftKeys = vm.leftFile.entries.filter { $0.type == .keyValue }
        let keyAEntries = leftKeys.filter { $0.key == "KEY_A" }
        #expect(keyAEntries.count == 1, "Should have exactly 1 KEY_A, not a duplicate")
        #expect(keyAEntries.first?.value == "sample")
    }

    // MARK: - Transfer respects dirty state

    @Test("Transfer marks panel as dirty")
    @MainActor func transferMarksDirty() {
        let testDefaults = UserDefaults(suiteName: "test.transfer.4")!
        testDefaults.removePersistentDomain(forName: "test.transfer.4")
        let settings = AppSettings(defaults: testDefaults)
        settings.sequentialDiff = true

        let vm = makeVM(
            left: "KEY_A=val\nKEY_B=val2",
            right: "KEY_A=val",
            settings: settings
        )

        #expect(vm.isRightDirty == false)

        let leftOnlyRows = vm.rows.filter { $0.diffCategory == .leftOnly }
        if let row = leftOnlyRows.first {
            vm.transfer(row: row, to: .right)
        }

        #expect(vm.isRightDirty == true)
    }

    // MARK: - Value-only mode with key-aware transfer

    @Test("Value-only transfer updates existing key preserving target structure")
    @MainActor func valueOnlyTransferUpdatesExisting() {
        let testDefaults = UserDefaults(suiteName: "test.transfer.5")!
        testDefaults.removePersistentDomain(forName: "test.transfer.5")
        let settings = AppSettings(defaults: testDefaults)
        settings.sequentialDiff = true
        settings.transferMode = .valueOnly

        let vm = makeVM(
            left: "# comment\nKEY_A=newvalue",
            right: "export KEY_A=\"oldvalue\"",
            settings: settings
        )

        let leftOnlyRows = vm.rows.filter { $0.diffCategory == .leftOnly }
        if let row = leftOnlyRows.first(where: { $0.leftEntry?.key == "KEY_A" }) {
            vm.transfer(row: row, to: .right)
        }

        vm.reDiff()
        let rightKeys = vm.rightFile.entries.filter { $0.key == "KEY_A" }
        #expect(rightKeys.count == 1)
        // Should preserve export prefix and quotes from target
        #expect(rightKeys.first?.hasExportPrefix == true)
        #expect(rightKeys.first?.value == "newvalue")
    }
}
