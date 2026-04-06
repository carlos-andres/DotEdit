import Foundation

/// Validates filenames against .env naming rules (DEC-027).
///
/// Accepted patterns:
/// - `.env`                        (exact match)
/// - `.env.local`, `.env.production` (prefix: `.env.*`)
/// - `dashboard-v2.env`            (suffix: `*.env`)
/// - `dashboard-v2.env.example`    (contains `.env.`)
///
/// Rejected regardless of pattern:
/// - Filenames ending in `.backup`, `.tmp`, `.temp`
enum FileValidator {

    /// Result of a file validation check.
    struct ValidationResult: Equatable {
        let isValid: Bool
        let reason: String?

        static let valid = ValidationResult(isValid: true, reason: nil)

        static func invalid(_ reason: String) -> ValidationResult {
            ValidationResult(isValid: false, reason: reason)
        }
    }

    // MARK: - Rejected Suffixes

    private static let rejectedSuffixes = [".backup", ".tmp", ".temp"]

    // MARK: - Public API

    /// Validate whether a filename matches any `.env` naming pattern.
    static func validate(filename: String) -> ValidationResult {
        // Accept: .env, .env.*, *.env, *.env.*
        let isEnvFile = filename.hasSuffix(".env") || filename.contains(".env.")

        guard isEnvFile else {
            Log.validation.debug("Rejected filename: \(filename, privacy: .public)")
            return .invalid("Filename must contain .env (got: \(filename))")
        }

        // Reject excluded suffixes
        for suffix in rejectedSuffixes {
            if filename.hasSuffix(suffix) {
                Log.validation.debug("Rejected suffix \(suffix, privacy: .public) in: \(filename, privacy: .public)")
                return .invalid("Files ending in \(suffix) are not allowed")
            }
        }

        Log.validation.debug("Accepted filename: \(filename, privacy: .public)")
        return .valid
    }

    /// Validate a file URL.
    static func validate(url: URL) -> ValidationResult {
        validate(filename: url.lastPathComponent)
    }
}
