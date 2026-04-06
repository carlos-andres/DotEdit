import Foundation
import Testing
@testable import DotEdit

@Suite("EnvParser")
struct EnvParserTests {

    // MARK: - Basic Key-Value

    @Test("Parses simple key=value")
    func simpleKeyValue() {
        let file = EnvParser.parse(content: "DB_HOST=localhost", filePath: "test")
        #expect(file.entries.count == 1)
        #expect(file.entries[0].type == .keyValue)
        #expect(file.entries[0].key == "DB_HOST")
        #expect(file.entries[0].value == "localhost")
        #expect(file.entries[0].quoteStyle == .none)
    }

    @Test("Parses empty value (KEY=)")
    func emptyValue() {
        let file = EnvParser.parse(content: "EMPTY_KEY=", filePath: "test")
        #expect(file.entries[0].type == .keyValue)
        #expect(file.entries[0].key == "EMPTY_KEY")
        #expect(file.entries[0].value == "")
    }

    @Test("Splits on first = only (value contains =)")
    func valueContainsEquals() {
        let file = EnvParser.parse(content: "DATABASE_URL=postgres://localhost/mydb", filePath: "test")
        #expect(file.entries[0].key == "DATABASE_URL")
        #expect(file.entries[0].value == "postgres://localhost/mydb")
    }

    @Test("Handles whitespace around =")
    func whitespaceAroundEquals() {
        let file = EnvParser.parse(content: "  KEY  =  value  ", filePath: "test")
        #expect(file.entries[0].key == "KEY")
        #expect(file.entries[0].value == "value")
    }

    // MARK: - Quoted Values

    @Test("Parses double-quoted value")
    func doubleQuoted() {
        let file = EnvParser.parse(content: "KEY=\"hello world\"", filePath: "test")
        #expect(file.entries[0].value == "hello world")
        #expect(file.entries[0].quoteStyle == .double)
    }

    @Test("Parses single-quoted value")
    func singleQuoted() {
        let file = EnvParser.parse(content: "KEY='hello world'", filePath: "test")
        #expect(file.entries[0].value == "hello world")
        #expect(file.entries[0].quoteStyle == .single)
    }

    @Test("Parses backtick-quoted value")
    func backtickQuoted() {
        let file = EnvParser.parse(content: "KEY=`hello world`", filePath: "test")
        #expect(file.entries[0].value == "hello world")
        #expect(file.entries[0].quoteStyle == .backtick)
    }

    @Test("Detects unclosed quote")
    func unclosedQuote() {
        let file = EnvParser.parse(content: "KEY=\"unclosed value", filePath: "test")
        #expect(file.entries[0].quoteStyle == .double)
        #expect(file.entries[0].warnings.contains(.unclosedQuote))
    }

    // MARK: - Comments

    @Test("Parses comment line")
    func commentLine() {
        let file = EnvParser.parse(content: "# This is a comment", filePath: "test")
        #expect(file.entries[0].type == .comment)
        #expect(file.entries[0].key == nil)
    }

    @Test("Inline comment is part of unquoted value")
    func inlineComment() {
        let file = EnvParser.parse(content: "KEY=value # comment", filePath: "test")
        #expect(file.entries[0].value == "value # comment")
    }

    @Test("Hash inside quotes is literal")
    func hashInsideQuotes() {
        let file = EnvParser.parse(content: "KEY=\"value # not a comment\"", filePath: "test")
        #expect(file.entries[0].value == "value # not a comment")
    }

    // MARK: - Blank Lines

    @Test("Parses blank line")
    func blankLine() {
        let file = EnvParser.parse(content: "", filePath: "test")
        #expect(file.entries[0].type == .blank)
    }

    @Test("Parses whitespace-only line as blank")
    func whitespaceOnlyLine() {
        let file = EnvParser.parse(content: "   ", filePath: "test")
        #expect(file.entries[0].type == .blank)
    }

    // MARK: - Export Prefix

    @Test("Detects export prefix")
    func exportPrefix() {
        let file = EnvParser.parse(content: "export DB_HOST=localhost", filePath: "test")
        #expect(file.entries[0].hasExportPrefix == true)
        #expect(file.entries[0].key == "DB_HOST")
        #expect(file.entries[0].value == "localhost")
    }

    @Test("Export with tab separator")
    func exportWithTab() {
        let file = EnvParser.parse(content: "export\tKEY=value", filePath: "test")
        #expect(file.entries[0].hasExportPrefix == true)
        #expect(file.entries[0].key == "KEY")
    }

    // MARK: - Malformed Lines

    @Test("Detects malformed line (no =)")
    func malformedLine() {
        let file = EnvParser.parse(content: "this is not valid", filePath: "test")
        #expect(file.entries[0].type == .malformed)
        #expect(file.entries[0].warnings.contains(.malformedLine))
    }

    // MARK: - Non-Standard Keys

    @Test("Warns on non-standard key with dots")
    func nonStandardKeyDots() {
        let file = EnvParser.parse(content: "app.debug=true", filePath: "test")
        #expect(file.entries[0].type == .keyValue)
        #expect(file.entries[0].warnings.contains(.nonStandardKey))
    }

    @Test("Warns on non-standard key with hyphens")
    func nonStandardKeyHyphens() {
        let file = EnvParser.parse(content: "app-debug=true", filePath: "test")
        #expect(file.entries[0].warnings.contains(.nonStandardKey))
    }

    @Test("No warning for standard key")
    func standardKey() {
        let file = EnvParser.parse(content: "APP_DEBUG=true", filePath: "test")
        #expect(!file.entries[0].warnings.contains(.nonStandardKey))
    }

    // MARK: - Duplicate Keys

    @Test("Detects duplicate keys")
    func duplicateKeys() {
        let content = "DB_HOST=a\nDB_PORT=3306\nDB_HOST=b"
        let file = EnvParser.parse(content: content, filePath: "test")
        let dbHostEntries = file.entries.filter { $0.key == "DB_HOST" }
        #expect(dbHostEntries.count == 2)
        #expect(dbHostEntries.allSatisfy { $0.warnings.contains(.duplicateKey) })
        #expect(file.duplicateKeys == Set(["DB_HOST"]))
    }

    @Test("No duplicate warning for unique keys")
    func uniqueKeys() {
        let content = "A=1\nB=2\nC=3"
        let file = EnvParser.parse(content: content, filePath: "test")
        #expect(file.entries.allSatisfy { !$0.warnings.contains(.duplicateKey) })
        #expect(file.duplicateKeys.isEmpty)
    }

    // MARK: - BOM Detection

    @Test("Detects UTF-8 BOM")
    func bomDetection() {
        let content = "\u{FEFF}KEY=value"
        let file = EnvParser.parse(content: content, filePath: "test")
        #expect(file.metadata.hasBOM == true)
        #expect(file.entries[0].key == "KEY")
    }

    @Test("No BOM on normal file")
    func noBOM() {
        let file = EnvParser.parse(content: "KEY=value", filePath: "test")
        #expect(file.metadata.hasBOM == false)
    }

    // MARK: - Line Endings

    @Test("Detects LF line endings")
    func lfLineEndings() {
        let file = EnvParser.parse(content: "A=1\nB=2", filePath: "test")
        #expect(file.metadata.originalLineEnding == .lf)
        #expect(file.entries.count == 2)
    }

    @Test("Detects CRLF line endings")
    func crlfLineEndings() {
        let file = EnvParser.parse(content: "A=1\r\nB=2", filePath: "test")
        #expect(file.metadata.originalLineEnding == .crlf)
        #expect(file.entries.count == 2)
    }

    @Test("Detects CR line endings")
    func crLineEndings() {
        let file = EnvParser.parse(content: "A=1\rB=2", filePath: "test")
        #expect(file.metadata.originalLineEnding == .cr)
        #expect(file.entries.count == 2)
    }

    // MARK: - Multiline Values

    @Test("Parses multiline double-quoted value")
    func multilineDoubleQuoted() {
        let content = "KEY=\"line1\nline2\nline3\""
        let file = EnvParser.parse(content: content, filePath: "test")
        #expect(file.entries.count == 1)
        #expect(file.entries[0].key == "KEY")
        #expect(file.entries[0].value == "line1\nline2\nline3")
        #expect(file.entries[0].quoteStyle == .double)
    }

    @Test("Parses multiline single-quoted value")
    func multilineSingleQuoted() {
        let content = "KEY='line1\nline2'"
        let file = EnvParser.parse(content: content, filePath: "test")
        #expect(file.entries.count == 1)
        #expect(file.entries[0].value == "line1\nline2")
    }

    @Test("Multiline unclosed quote warns")
    func multilineUnclosed() {
        let content = "KEY=\"line1\nline2\nline3"
        let file = EnvParser.parse(content: content, filePath: "test")
        #expect(file.entries[0].warnings.contains(.unclosedQuote))
    }

    // MARK: - Mixed File

    @Test("Parses complete .env file with mixed line types")
    func mixedFile() {
        let content = """
        # Database settings
        DB_HOST=localhost
        DB_PORT=3306
        DB_PASS="my-sample"

        # API
        export API_KEY=sample
        MALFORMED_LINE
        EMPTY=
        """
        let file = EnvParser.parse(content: content, filePath: "test")

        let types = file.entries.map(\.type)
        #expect(types == [
            .comment,    // # Database settings
            .keyValue,   // DB_HOST
            .keyValue,   // DB_PORT
            .keyValue,   // DB_PASS
            .blank,      // empty line
            .comment,    // # API
            .keyValue,   // export API_KEY
            .malformed,  // MALFORMED_LINE
            .keyValue,   // EMPTY=
        ])

        #expect(file.keyCount == 5)
        #expect(file.entries[3].quoteStyle == .double)
        #expect(file.entries[6].hasExportPrefix == true)
        #expect(file.entries[8].value == "")
    }

    // MARK: - Binary Detection

    @Test("Detects binary content")
    func binaryDetection() {
        let data = Data([0x48, 0x65, 0x6C, 0x00, 0x6F])
        #expect(EnvParser.isBinaryContent(data) == true)
    }

    @Test("Accepts text content")
    func textContent() {
        let data = "KEY=value\n".data(using: .utf8)!
        #expect(EnvParser.isBinaryContent(data) == false)
    }

    // MARK: - Serialization

    @Test("Round-trips content through parse and serialize")
    func roundTrip() {
        let original = "DB_HOST=localhost\nDB_PORT=3306\n# comment\n"
        let file = EnvParser.parse(content: original, filePath: "test")
        let serialized = EnvParser.serialize(entries: file.entries)
        #expect(serialized == "DB_HOST=localhost\nDB_PORT=3306\n# comment\n")
    }

    // MARK: - EnvFile Computed Properties

    @Test("keyValueEntries filters correctly")
    func keyValueEntriesFilter() {
        let content = "# comment\nKEY=val\n\nKEY2=val2"
        let file = EnvParser.parse(content: content, filePath: "test")
        #expect(file.keyValueEntries.count == 2)
    }

    @Test("keys returns unique keys in order")
    func uniqueKeysOrdered() {
        let content = "A=1\nB=2\nA=3\nC=4"
        let file = EnvParser.parse(content: content, filePath: "test")
        #expect(file.keys == ["A", "B", "C"])
    }
}
