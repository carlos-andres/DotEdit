import Foundation

/// Loads .env files from disk, handling BOM, line endings, binary detection, and permissions.
enum FileLoader {

    // MARK: - Errors

    /// Maximum allowed file size: 2 MB (DEC-053)
    static let maxFileSize: UInt64 = 2 * 1024 * 1024

    enum LoadError: LocalizedError, Equatable {
        case fileNotFound(String)
        case fileTooLarge(String, UInt64)
        case binaryFile(String)
        case readError(String)
        case encodingError(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                "File not found: \(URL(fileURLWithPath: path).lastPathComponent)"
            case .fileTooLarge(let path, let size):
                "File too large (\(String(format: "%.1f", Double(size) / 1_048_576)) MB): \(URL(fileURLWithPath: path).lastPathComponent). Maximum is 2 MB."
            case .binaryFile(let path):
                "Not a valid text file (binary content detected): \(URL(fileURLWithPath: path).lastPathComponent)"
            case .readError(let message):
                "Failed to read file: \(message)"
            case .encodingError(let path):
                "File is not valid UTF-8: \(URL(fileURLWithPath: path).lastPathComponent)"
            }
        }
    }

    // MARK: - Helpers

    /// Check if a URL is on a non-local (network) volume (BL-010).
    static func isNonLocalVolume(url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey]),
              let isLocal = values.volumeIsLocal else {
            return false
        }
        return !isLocal
    }

    // MARK: - Public API

    /// Load an .env file from the given URL.
    /// Resolves symlinks, detects binary content, normalizes encoding, and parses via `EnvParser`.
    /// Handles security-scoped resource access for sandboxed apps.
    static func load(url: URL) throws -> EnvFile {
        let fileManager = FileManager.default

        // Start security-scoped access (required for sandbox).
        // Safe to call on non-scoped URLs — just returns false.
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        Log.fileIO.debug("Loading \(url.lastPathComponent, privacy: .public), securityScoped=\(didStartAccess)")

        // Resolve symlinks
        let resolvedURL = url.resolvingSymlinksInPath()
        let path = resolvedURL.path

        // Check file exists
        guard fileManager.fileExists(atPath: path) else {
            throw LoadError.fileNotFound(path)
        }

        // Reject oversized files (DEC-053)
        if let attrs = try? fileManager.attributesOfItem(atPath: path),
           let fileSize = attrs[.size] as? UInt64,
           fileSize > Self.maxFileSize {
            throw LoadError.fileTooLarge(path, fileSize)
        }

        // Read raw data
        let data: Data
        do {
            data = try Data(contentsOf: resolvedURL)
        } catch {
            Log.fileIO.error("Read failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            // BL-010: Enhance error message for non-local volumes
            var message = error.localizedDescription
            if Self.isNonLocalVolume(url: resolvedURL) {
                message += " — network volume may be disconnected"
            }
            throw LoadError.readError(message)
        }

        // Reject binary files (check first 8KB for null bytes)
        let checkLength = min(data.count, 8192)
        let sample = data.prefix(checkLength)
        if EnvParser.isBinaryContent(sample) {
            throw LoadError.binaryFile(path)
        }

        // Decode as UTF-8
        guard let content = String(data: data, encoding: .utf8) else {
            throw LoadError.encodingError(path)
        }

        // Detect read-only (check under security scope so sandbox doesn't false-positive)
        let isReadOnly = !fileManager.isWritableFile(atPath: path)

        // Parse via EnvParser (handles BOM stripping, line ending detection, etc.)
        let parsed = EnvParser.parse(content: content, filePath: path)

        // Return with isReadOnly set
        return EnvFile(
            filePath: parsed.filePath,
            entries: parsed.entries,
            metadata: parsed.metadata,
            isReadOnly: isReadOnly
        )
    }
}
