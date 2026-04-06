import Foundation

/// Manages a list of recently opened .env file URLs, persisted via UserDefaults as bookmark data.
final class RecentFilesManager {

    // MARK: - Constants

    static let maxRecents = 10
    private let defaultsKey: String
    private let defaults: UserDefaults

    // MARK: - Init

    /// - Parameters:
    ///   - key: The UserDefaults key for storage. Default `"recentEnvFiles"`.
    ///   - defaults: The UserDefaults instance. Default `.standard`.
    init(key: String = "recentEnvFiles", defaults: UserDefaults = .standard) {
        self.defaultsKey = key
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Add a file URL to the recents list.
    /// Moves to front if already present. Trims to `maxRecents`.
    func addFile(url: URL) {
        // Start security scope so we can create a scoped bookmark
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        var bookmarks = loadBookmarks()

        // Remove existing entry for same path
        bookmarks.removeAll { resolveBookmark($0)?.path == url.path }

        // Try security-scoped bookmark first, fall back to basic
        let bookmark: Data
        if let scoped = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            bookmark = scoped
            Log.fileIO.debug("Created scoped bookmark: \(url.lastPathComponent, privacy: .public)")
        } else if let basic = try? url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            bookmark = basic
            Log.fileIO.debug("Created basic bookmark (scoped failed): \(url.lastPathComponent, privacy: .public)")
        } else {
            Log.fileIO.error("Failed to create any bookmark for \(url.lastPathComponent, privacy: .public)")
            return
        }

        // Insert at front
        bookmarks.insert(bookmark, at: 0)

        // Trim
        if bookmarks.count > Self.maxRecents {
            bookmarks = Array(bookmarks.prefix(Self.maxRecents))
        }

        saveBookmarks(bookmarks)
        Log.fileIO.debug("Saved \(bookmarks.count) recents to [\(self.defaultsKey, privacy: .public)]")
    }

    /// Get the list of recent file URLs, filtering out files that no longer exist.
    func recentFiles() -> [URL] {
        let bookmarks = loadBookmarks()
        Log.fileIO.debug("Loading \(bookmarks.count) bookmarks from [\(self.defaultsKey, privacy: .public)]")

        var validURLs: [URL] = []
        var validBookmarks: [Data] = []

        for bookmark in bookmarks {
            guard let url = resolveBookmark(bookmark) else {
                Log.fileIO.debug("Failed to resolve a bookmark in [\(self.defaultsKey, privacy: .public)]")
                continue
            }

            // Activate security scope to check file existence on sandboxed paths
            let didAccess = url.startAccessingSecurityScopedResource()
            let exists = FileManager.default.fileExists(atPath: url.path)
            if didAccess { url.stopAccessingSecurityScopedResource() }

            if exists {
                validURLs.append(url)
                validBookmarks.append(bookmark)
            } else {
                Log.fileIO.debug("Pruning stale recent: \(url.lastPathComponent, privacy: .public)")
            }
        }

        // Prune stale entries
        if validBookmarks.count != bookmarks.count {
            saveBookmarks(validBookmarks)
        }

        Log.fileIO.debug("Returning \(validURLs.count) recents from [\(self.defaultsKey, privacy: .public)]")
        return validURLs
    }

    /// Clear all recent files.
    func clearRecents() {
        defaults.removeObject(forKey: defaultsKey)
    }

    // MARK: - Private

    private func loadBookmarks() -> [Data] {
        defaults.array(forKey: defaultsKey) as? [Data] ?? []
    }

    private func saveBookmarks(_ bookmarks: [Data]) {
        defaults.set(bookmarks, forKey: defaultsKey)
    }

    /// Resolve bookmark data to a URL. If the bookmark is stale, refresh it in-place.
    /// Returns a tuple of (url, refreshedBookmarkData?) so callers can persist the update.
    private func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        // Try security-scoped first
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            if isStale {
                Log.fileIO.debug("Stale bookmark detected for \(url.lastPathComponent, privacy: .public), refreshing")
                refreshBookmark(for: url, replacing: data)
            }
            return url
        }
        // Do not fall back to basic (unscoped) resolution — stale scoped bookmarks
        // should be refreshed, not silently downgraded to unscoped access.
        return nil
    }

    /// Re-create bookmark data from a resolved URL and update the stored entry.
    private func refreshBookmark(for url: URL, replacing oldData: Data) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let newData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            Log.fileIO.warning("Failed to refresh stale bookmark for \(url.lastPathComponent, privacy: .public)")
            return
        }

        var bookmarks = loadBookmarks()
        if let index = bookmarks.firstIndex(of: oldData) {
            bookmarks[index] = newData
            saveBookmarks(bookmarks)
            Log.fileIO.debug("Refreshed stale bookmark for \(url.lastPathComponent, privacy: .public)")
        }
    }
}
