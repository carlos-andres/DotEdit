import Foundation
import Testing
@testable import DotEdit

// MARK: - FileLoader Tests

@Suite("FileLoader")
struct FileLoaderTests {

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DotEditTests-\(UUID().uuidString)")
    }

    private func createTempDir() throws -> URL {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Loads valid .env file")
    func loadValidFile() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        try "DB_HOST=localhost\nDB_PORT=3306".write(to: fileURL, atomically: true, encoding: .utf8)

        let envFile = try FileLoader.load(url: fileURL)
        #expect(envFile.entries.count == 2)
        #expect(envFile.entries[0].key == "DB_HOST")
        #expect(envFile.entries[1].key == "DB_PORT")
        #expect(envFile.isReadOnly == false)
    }

    @Test("Detects and strips BOM")
    func loadFileWithBOM() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        let bomContent = "\u{FEFF}API_KEY=sample"
        try bomContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let envFile = try FileLoader.load(url: fileURL)
        #expect(envFile.metadata.hasBOM == true)
        #expect(envFile.entries[0].key == "API_KEY")
        #expect(envFile.entries[0].value == "sample")
    }

    @Test("Rejects binary file")
    func rejectBinaryFile() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        let binaryData = Data([0x48, 0x65, 0x6C, 0x00, 0x6F, 0x00, 0x21])
        try binaryData.write(to: fileURL)

        #expect(throws: FileLoader.LoadError.self) {
            try FileLoader.load(url: fileURL)
        }
    }

    @Test("Detects read-only file")
    func detectReadOnlyFile() throws {
        let dir = try createTempDir()
        defer {
            // Restore permissions for cleanup
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: dir.appendingPathComponent(".env").path
            )
            try? FileManager.default.removeItem(at: dir)
        }

        let fileURL = dir.appendingPathComponent(".env")
        try "KEY=value".write(to: fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444],
            ofItemAtPath: fileURL.path
        )

        let envFile = try FileLoader.load(url: fileURL)
        #expect(envFile.isReadOnly == true)
    }

    @Test("Resolves symlinks")
    func resolveSymlinks() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let realFile = dir.appendingPathComponent(".env.real")
        try "SYMLINK_TEST=yes".write(to: realFile, atomically: true, encoding: .utf8)

        let linkURL = dir.appendingPathComponent(".env")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: realFile)

        let envFile = try FileLoader.load(url: linkURL)
        #expect(envFile.entries[0].key == "SYMLINK_TEST")
        #expect(envFile.entries[0].value == "yes")
    }

    @Test("Normalizes CRLF line endings")
    func normalizeCRLF() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        try "A=1\r\nB=2\r\nC=3".write(to: fileURL, atomically: true, encoding: .utf8)

        let envFile = try FileLoader.load(url: fileURL)
        #expect(envFile.entries.count == 3)
        #expect(envFile.metadata.originalLineEnding == .crlf)
        #expect(envFile.entries[0].key == "A")
        #expect(envFile.entries[2].key == "C")
    }

    @Test("Normalizes CR line endings")
    func normalizeCR() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        try "X=1\rY=2".write(to: fileURL, atomically: true, encoding: .utf8)

        let envFile = try FileLoader.load(url: fileURL)
        #expect(envFile.entries.count == 2)
        #expect(envFile.metadata.originalLineEnding == .cr)
    }

    @Test("Throws for missing file")
    func missingFile() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString)/.env")
        #expect(throws: FileLoader.LoadError.self) {
            try FileLoader.load(url: url)
        }
    }
}

// MARK: - FileSaver Tests

@Suite("FileSaver")
struct FileSaverTests {

    private func createTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DotEditTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Saves content and verifies")
    func saveContent() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        let content = "DB_HOST=localhost\nDB_PORT=3306"

        try FileSaver.save(content: content, to: fileURL, createBackup: false)

        let saved = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(saved == content)
    }

    @Test("Creates backup with correct naming for .env")
    func backupNamingDotEnv() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        try "ORIGINAL=true".write(to: fileURL, atomically: true, encoding: .utf8)

        try FileSaver.save(content: "UPDATED=true", to: fileURL, createBackup: true)

        let backupURL = dir.appendingPathComponent(".env.backup")
        let backupContent = try String(contentsOf: backupURL, encoding: .utf8)
        #expect(backupContent == "ORIGINAL=true")

        let updatedContent = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(updatedContent == "UPDATED=true")
    }

    @Test("Creates backup with correct naming for .env.production")
    func backupNamingDotEnvProduction() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env.production")
        try "PROD=true".write(to: fileURL, atomically: true, encoding: .utf8)

        try FileSaver.save(content: "PROD=false", to: fileURL, createBackup: true)

        let backupURL = dir.appendingPathComponent(".env.production.backup")
        let backupContent = try String(contentsOf: backupURL, encoding: .utf8)
        #expect(backupContent == "PROD=true")
    }

    @Test("Atomic write produces file at destination")
    func atomicWrite() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        try FileSaver.save(content: "KEY=val", to: fileURL, createBackup: false)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("No backup when createBackup is false")
    func noBackup() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        try "ORIGINAL=yes".write(to: fileURL, atomically: true, encoding: .utf8)

        try FileSaver.save(content: "UPDATED=yes", to: fileURL, createBackup: false)

        let backupURL = dir.appendingPathComponent(".env.backup")
        #expect(!FileManager.default.fileExists(atPath: backupURL.path))
    }

    @Test("Saves EnvFile preserving line endings")
    func saveEnvFile() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        try "A=1\r\nB=2".write(to: fileURL, atomically: true, encoding: .utf8)

        let envFile = try FileLoader.load(url: fileURL)
        try FileSaver.save(envFile, createBackup: false)

        let saved = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(saved.contains("\r\n"))
    }

    @Test("Backup URL computation")
    func backupURLComputation() {
        let envURL = URL(fileURLWithPath: "/tmp/.env")
        #expect(FileSaver.backupURL(for: envURL).lastPathComponent == ".env.backup")

        let prodURL = URL(fileURLWithPath: "/tmp/.env.production")
        #expect(FileSaver.backupURL(for: prodURL).lastPathComponent == ".env.production.backup")
    }

    // MARK: - Sandbox-safe atomic write tests (DEC-055)

    @Test("No temp files left in source directory after save")
    func noTempFilesInSourceDir() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        try "ORIGINAL=yes".write(to: fileURL, atomically: true, encoding: .utf8)

        try FileSaver.save(content: "UPDATED=yes", to: fileURL, createBackup: false)

        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let tempFiles = contents.filter { $0.hasPrefix(".dotedit_tmp_") }
        #expect(tempFiles.isEmpty, "Temp files should not remain in source directory")
    }

    @Test("Save fails with clear error when directory is not writable")
    func saveFailsWithReadOnlyDirectory() throws {
        let dir = try createTempDir()
        let fileURL = dir.appendingPathComponent(".env")
        try "ORIGINAL=yes".write(to: fileURL, atomically: true, encoding: .utf8)

        // Make directory read-only (POSIX restriction — sandbox uses security scopes instead)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: dir.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: dir.path
            )
            try? FileManager.default.removeItem(at: dir)
        }

        #expect(throws: FileSaver.SaveError.self) {
            try FileSaver.save(content: "UPDATED=yes", to: fileURL, createBackup: false)
        }
    }

    @Test("Temp file written to app sandbox temp dir, not source directory")
    func tempFileUsesAppTempDir() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        try "ORIGINAL=yes".write(to: fileURL, atomically: true, encoding: .utf8)

        try FileSaver.save(content: "UPDATED=yes", to: fileURL, createBackup: false)

        // Verify no .dotedit_tmp files were created in the source directory
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let tempFiles = contents.filter { $0.hasPrefix(".dotedit_tmp_") }
        #expect(tempFiles.isEmpty, "Temp files must use app temp dir, not source dir")

        // Verify the save actually worked
        let saved = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(saved == "UPDATED=yes")
    }

    @Test("Preserves POSIX permissions after atomic replace")
    func preservesPermissionsAfterReplace() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        try "SECRET=sample".write(to: fileURL, atomically: true, encoding: .utf8)

        // Set restrictive permissions (0600 = owner read/write only)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )

        try FileSaver.save(content: "SECRET=changed", to: fileURL, createBackup: false)

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value
        #expect(perms == 0o600, "Permissions should be preserved after save")
    }

    @Test("Save to new file path (no pre-existing file)")
    func saveToNewFile() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env.new")
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        try FileSaver.save(content: "NEW_KEY=value", to: fileURL, createBackup: false)

        let saved = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(saved == "NEW_KEY=value")
    }

    @Test("Multiple consecutive saves preserve content correctly")
    func consecutiveSaves() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        try "V=1".write(to: fileURL, atomically: true, encoding: .utf8)

        for i in 2...5 {
            try FileSaver.save(content: "V=\(i)", to: fileURL, createBackup: false)
            let saved = try String(contentsOf: fileURL, encoding: .utf8)
            #expect(saved == "V=\(i)", "Content should match after save \(i)")
        }
    }

    @Test("No temp files left in app temp dir after save")
    func noTempFilesLeakedInAppTemp() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let tempDir = FileManager.default.temporaryDirectory
        let beforeContents = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
        )

        let fileURL = dir.appendingPathComponent(".env")
        try "KEY=val".write(to: fileURL, atomically: true, encoding: .utf8)
        try FileSaver.save(content: "KEY=updated", to: fileURL, createBackup: false)

        let afterContents = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: tempDir.path)) ?? []
        )
        let leaked = afterContents.subtracting(beforeContents)
            .filter { $0.hasPrefix(".dotedit_tmp_") }
        #expect(leaked.isEmpty, "No .dotedit_tmp_ files should remain in app temp directory")
    }

    @Test("Fallback backup URL uses Application Support")
    func fallbackBackupURLComputation() {
        let url = URL(fileURLWithPath: "/some/project/.env.staging")
        let fallback = FileSaver.fallbackBackupURL(for: url)
        #expect(fallback != nil)
        #expect(fallback!.path.contains("DotEdit/backups"))
        #expect(fallback!.lastPathComponent == "project_.env.staging.backup")
    }
}

// MARK: - FileValidator Tests

@Suite("FileValidator")
struct FileValidatorTests {

    @Test("Accepts .env")
    func acceptDotEnv() {
        let result = FileValidator.validate(filename: ".env")
        #expect(result.isValid)
    }

    @Test("Accepts .env.local")
    func acceptDotEnvLocal() {
        let result = FileValidator.validate(filename: ".env.local")
        #expect(result.isValid)
    }

    @Test("Accepts .env.production")
    func acceptDotEnvProduction() {
        let result = FileValidator.validate(filename: ".env.production")
        #expect(result.isValid)
    }

    @Test("Accepts .env.example")
    func acceptDotEnvExample() {
        let result = FileValidator.validate(filename: ".env.example")
        #expect(result.isValid)
    }

    @Test("Accepts dashboard-v2.env.example (prefixed)")
    func acceptPrefixedEnvExample() {
        let result = FileValidator.validate(filename: "dashboard-v2.env.example")
        #expect(result.isValid)
    }

    @Test("Accepts myapp.env (prefixed, no suffix)")
    func acceptPrefixedEnv() {
        let result = FileValidator.validate(filename: "myapp.env")
        #expect(result.isValid)
    }

    @Test("Accepts app.env.local (prefixed with suffix)")
    func acceptPrefixedEnvLocal() {
        let result = FileValidator.validate(filename: "app.env.local")
        #expect(result.isValid)
    }

    @Test("Rejects dashboard-v2.env.backup (prefixed but excluded suffix)")
    func rejectPrefixedEnvBackup() {
        let result = FileValidator.validate(filename: "dashboard-v2.env.backup")
        #expect(!result.isValid)
        #expect(result.reason?.contains(".backup") == true)
    }

    @Test("Rejects .env.backup")
    func rejectDotEnvBackup() {
        let result = FileValidator.validate(filename: ".env.backup")
        #expect(!result.isValid)
        #expect(result.reason?.contains(".backup") == true)
    }

    @Test("Rejects .env.tmp")
    func rejectDotEnvTmp() {
        let result = FileValidator.validate(filename: ".env.tmp")
        #expect(!result.isValid)
        #expect(result.reason?.contains(".tmp") == true)
    }

    @Test("Rejects .env.temp")
    func rejectDotEnvTemp() {
        let result = FileValidator.validate(filename: ".env.temp")
        #expect(!result.isValid)
        #expect(result.reason?.contains(".temp") == true)
    }

    @Test("Rejects config.yaml")
    func rejectConfigYaml() {
        let result = FileValidator.validate(filename: "config.yaml")
        #expect(!result.isValid)
    }

    @Test("Rejects notes.txt")
    func rejectNotesTxt() {
        let result = FileValidator.validate(filename: "notes.txt")
        #expect(!result.isValid)
    }

    @Test("Rejects .envrc")
    func rejectEnvrc() {
        let result = FileValidator.validate(filename: ".envrc")
        #expect(!result.isValid)
    }

    @Test("Validates URL")
    func validateURL() {
        let url = URL(fileURLWithPath: "/tmp/.env.local")
        let result = FileValidator.validate(url: url)
        #expect(result.isValid)
    }
}

// MARK: - RecentFilesManager Tests

@Suite("RecentFilesManager")
struct RecentFilesManagerTests {

    /// Creates a manager with an isolated UserDefaults key to avoid test pollution.
    private func makeManager() -> RecentFilesManager {
        let key = "test-recents-\(UUID().uuidString)"
        return RecentFilesManager(key: key)
    }

    private func createTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DotEditTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Add and retrieve recent file")
    func addAndRetrieve() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = makeManager()
        let fileURL = dir.appendingPathComponent(".env")
        try "KEY=val".write(to: fileURL, atomically: true, encoding: .utf8)

        manager.addFile(url: fileURL)
        let recents = manager.recentFiles()
        #expect(recents.count == 1)
        #expect(recents[0].lastPathComponent == ".env")
    }

    @Test("Clear recents")
    func clearRecents() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = makeManager()
        let fileURL = dir.appendingPathComponent(".env")
        try "KEY=val".write(to: fileURL, atomically: true, encoding: .utf8)

        manager.addFile(url: fileURL)
        #expect(manager.recentFiles().count == 1)

        manager.clearRecents()
        #expect(manager.recentFiles().isEmpty)
    }

    @Test("Respects max limit")
    func maxLimit() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = makeManager()

        // Create 12 files
        for i in 0..<12 {
            let fileURL = dir.appendingPathComponent(".env.\(i)")
            try "KEY=\(i)".write(to: fileURL, atomically: true, encoding: .utf8)
            manager.addFile(url: fileURL)
        }

        let recents = manager.recentFiles()
        #expect(recents.count == RecentFilesManager.maxRecents)
    }

    @Test("Most recent first")
    func mostRecentFirst() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = makeManager()

        let first = dir.appendingPathComponent(".env.first")
        try "A=1".write(to: first, atomically: true, encoding: .utf8)
        manager.addFile(url: first)

        let second = dir.appendingPathComponent(".env.second")
        try "B=2".write(to: second, atomically: true, encoding: .utf8)
        manager.addFile(url: second)

        let recents = manager.recentFiles()
        #expect(recents[0].lastPathComponent == ".env.second")
        #expect(recents[1].lastPathComponent == ".env.first")
    }

    @Test("Removes stale entries")
    func removesStaleEntries() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let manager = makeManager()

        let fileURL = dir.appendingPathComponent(".env")
        try "KEY=val".write(to: fileURL, atomically: true, encoding: .utf8)
        manager.addFile(url: fileURL)

        // Delete the file
        try FileManager.default.removeItem(at: fileURL)

        let recents = manager.recentFiles()
        #expect(recents.isEmpty)
    }
}

// MARK: - FileWatcher Tests

@Suite("FileWatcher")
struct FileWatcherTests {

    /// Use NSTemporaryDirectory() which works inside the app sandbox container.
    private func createTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DotEditTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Watch and stop tracking")
    func watchAndStop() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        try "KEY=val".write(to: fileURL, atomically: true, encoding: .utf8)

        let watcher = FileWatcher()
        watcher.watch(url: fileURL)
        #expect(watcher.isWatching(url: fileURL))
        #expect(watcher.watchCount == 1)

        watcher.stopWatching(url: fileURL)
        #expect(!watcher.isWatching(url: fileURL))
        #expect(watcher.watchCount == 0)
    }

    @Test("StopAll clears all watches")
    func stopAll() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file1 = dir.appendingPathComponent(".env.one")
        let file2 = dir.appendingPathComponent(".env.two")
        try "A=1".write(to: file1, atomically: true, encoding: .utf8)
        try "B=2".write(to: file2, atomically: true, encoding: .utf8)

        let watcher = FileWatcher()
        watcher.watch(url: file1)
        watcher.watch(url: file2)
        #expect(watcher.watchCount == 2)

        watcher.stopAll()
        #expect(watcher.watchCount == 0)
    }

    @Test("Suppress and unsuppress")
    func suppressAndUnsuppress() throws {
        let watcher = FileWatcher()
        watcher.suppress()
        watcher.unsuppress()
    }

    @Test("No double-watch for same URL")
    func noDoubleWatch() throws {
        let dir = try createTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent(".env")
        try "KEY=val".write(to: fileURL, atomically: true, encoding: .utf8)

        let watcher = FileWatcher()
        watcher.watch(url: fileURL)
        watcher.watch(url: fileURL) // duplicate
        #expect(watcher.watchCount == 1)

        watcher.stopAll()
    }
}
