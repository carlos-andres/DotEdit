import Foundation
import os

/// Saves .env files to disk with atomic writes and optional backup creation.
enum FileSaver {

    // MARK: - Errors

    enum SaveError: LocalizedError, Equatable {
        case writeError(String)
        case encodingError

        var errorDescription: String? {
            switch self {
            case .writeError(let message):
                "Failed to save file: \(message)"
            case .encodingError:
                "Failed to encode content as UTF-8"
            }
        }
    }

    // MARK: - Public API

    /// Save an `EnvFile` to its original path.
    /// - Parameters:
    ///   - file: The env file to save.
    ///   - createBackup: Whether to create a `.backup` copy of the original first. Default `true`.
    ///   - securityScopedURL: The original security-scoped URL for sandbox access. Default `nil`.
    /// - Returns: Optional warning message if backup was skipped or relocated.
    @discardableResult
    static func save(
        _ file: EnvFile,
        createBackup: Bool = true,
        securityScopedURL: URL? = nil
    ) throws -> String? {
        let url = URL(fileURLWithPath: file.filePath)
        let content = EnvParser.serialize(
            entries: file.entries,
            lineEnding: file.metadata.originalLineEnding
        )
        return try save(content: content, to: url, createBackup: createBackup, securityScopedURL: securityScopedURL)
    }

    /// Save string content to a URL with atomic write and optional backup.
    /// - Parameters:
    ///   - content: The string content to write.
    ///   - url: The destination file URL.
    ///   - createBackup: Whether to backup the original file first. Default `true`.
    ///   - securityScopedURL: The original security-scoped URL for sandbox access. Default `nil`.
    /// - Returns: Optional warning message if backup was skipped or relocated.
    @discardableResult
    static func save(
        content: String,
        to url: URL,
        createBackup: Bool = true,
        securityScopedURL: URL? = nil
    ) throws -> String? {
        // Prune stale fallback backups that may contain plaintext secrets
        pruneOldBackups()

        guard let data = content.data(using: .utf8) else {
            throw SaveError.encodingError
        }

        // Start security-scoped access if available (DEC-055)
        let scopedURL = securityScopedURL ?? url
        let didStartAccess = scopedURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                scopedURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        var warning: String?

        // Create backup of original if it exists and backup is requested
        if createBackup && fileManager.fileExists(atPath: url.path) {
            warning = createBackupFile(for: url, fileManager: fileManager)
        }

        // Capture original file permissions before overwriting (DEC-052)
        let originalPermissions: UInt16?
        if fileManager.fileExists(atPath: url.path) {
            let attrs = try? fileManager.attributesOfItem(atPath: url.path)
            originalPermissions = (attrs?[.posixPermissions] as? NSNumber)?.uint16Value
        } else {
            originalPermissions = nil
        }

        // Atomic write: write to app temp dir, then replace in-place (DEC-055)
        // Uses app's sandbox temp directory (always writable) instead of the
        // source directory, which may not be writable under security-scoped access.
        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent(".dotedit_tmp_\(UUID().uuidString)")

        do {
            try data.write(to: tempURL)

            if fileManager.fileExists(atPath: url.path) {
                // replaceItemAt atomically swaps the files — works with security-scoped URLs
                _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: url)
            }

            // Restore original file permissions (DEC-052)
            if let permissions = originalPermissions {
                try? fileManager.setAttributes(
                    [.posixPermissions: NSNumber(value: permissions)],
                    ofItemAtPath: url.path
                )
            }
        } catch {
            // Clean up temp file on failure
            try? fileManager.removeItem(at: tempURL)
            throw SaveError.writeError(error.localizedDescription)
        }

        return warning
    }

    // MARK: - Backup

    /// Attempt to create a backup file. Returns a warning if backup was skipped or relocated.
    /// Backup failure is non-fatal (DEC-055).
    private static func createBackupFile(for url: URL, fileManager: FileManager) -> String? {
        let backupURL = backupURL(for: url)

        // Try in-place backup first
        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: url, to: backupURL)
            return nil // Success, no warning
        } catch {
            Log.fileIO.warning("In-place backup failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        // Fallback: backup to Application Support (silent — not user-facing)
        if let fallbackURL = fallbackBackupURL(for: url) {
            do {
                if fileManager.fileExists(atPath: fallbackURL.path) {
                    try fileManager.removeItem(at: fallbackURL)
                }
                try fileManager.copyItem(at: url, to: fallbackURL)
                Log.fileIO.info("Backup saved to fallback location: \(fallbackURL.path, privacy: .public)")
                return "Backup stored outside original location (Application Support). It will be auto-removed after 7 days."
            } catch {
                Log.fileIO.warning("Fallback backup also failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        Log.fileIO.warning("Backup skipped entirely for \(url.lastPathComponent, privacy: .public)")
        return nil // Backup is best-effort, don't surface as user-facing warning
    }

    // MARK: - Backup Naming

    /// Compute the backup URL for a given file URL.
    /// `.env` -> `.env.backup`, `.env.production` -> `.env.production.backup`
    static func backupURL(for url: URL) -> URL {
        let directory = url.deletingLastPathComponent()
        let filename = url.lastPathComponent
        let backupFilename = filename + ".backup"
        return directory.appendingPathComponent(backupFilename)
    }

    /// Maximum age for fallback backups before automatic pruning.
    private static let fallbackBackupMaxAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    /// Remove fallback backups older than `fallbackBackupMaxAge`.
    /// Called at the start of each save to prevent unbounded accumulation of plaintext secrets.
    static func pruneOldBackups() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }

        let backupDir = appSupport.appendingPathComponent("DotEdit/backups", isDirectory: true)
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-fallbackBackupMaxAge)
        for fileURL in contents {
            guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            try? fileManager.removeItem(at: fileURL)
            Log.fileIO.info("Pruned old fallback backup: \(fileURL.lastPathComponent, privacy: .public)")
        }
    }

    /// Fallback backup location in Application Support/DotEdit/backups/.
    /// WARNING: This directory stores plaintext .env content outside the original file location.
    /// Any process with Application Support access can read these files.
    /// Backups are pruned after 7 days by `pruneOldBackups()`.
    /// Uses parent directory name + filename to avoid collisions.
    static func fallbackBackupURL(for url: URL) -> URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let backupDir = appSupport.appendingPathComponent("DotEdit/backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let dirName = url.deletingLastPathComponent().lastPathComponent
        let filename = url.lastPathComponent
        return backupDir.appendingPathComponent("\(dirName)_\(filename).backup")
    }
}
