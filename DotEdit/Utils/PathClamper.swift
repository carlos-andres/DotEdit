import Foundation

/// Clamps a file path to show `../parent/filename` for compact display.
enum PathClamper {
    /// Returns a clamped path: `../parent/filename`.
    /// If path has no parent beyond root, returns just the filename.
    static func clamp(_ path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let filename = url.lastPathComponent
        let parent = url.deletingLastPathComponent().lastPathComponent

        if parent.isEmpty || parent == "/" || parent == "." {
            return filename
        }
        return "../\(parent)/\(filename)"
    }

    /// Returns a clamped path from a URL.
    static func clamp(_ url: URL) -> String {
        clamp(url.path)
    }
}
