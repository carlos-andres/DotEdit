import Foundation

/// Watches file URLs for external modifications using DispatchSource file monitoring.
/// All public API must be called from the main thread.
final class FileWatcher: @unchecked Sendable {

    // MARK: - Types

    typealias ChangeHandler = @Sendable (URL) -> Void

    // MARK: - State

    private let lock = NSLock()
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var fileDescriptors: [String: Int32] = [:]
    private let queue = DispatchQueue(label: "com.dotedit.filewatcher", qos: .utility)
    private var changeHandler: ChangeHandler?
    private var isSuppressed = false
    /// Timestamp of the last self-initiated write, used to ignore FS events that arrive late.
    private var lastWriteTimestamp: Date?

    // MARK: - Init

    init(onChange: ChangeHandler? = nil) {
        self.changeHandler = onChange
    }

    deinit {
        lock.lock()
        for (_, source) in sources {
            source.cancel()
        }
        sources.removeAll()
        fileDescriptors.removeAll()
        lock.unlock()
    }

    // MARK: - Public API

    /// Set or replace the change handler.
    func setChangeHandler(_ handler: @escaping ChangeHandler) {
        lock.lock()
        self.changeHandler = handler
        lock.unlock()
    }

    /// Start watching a file URL for changes.
    func watch(url: URL) {
        let path = url.resolvingSymlinksInPath().path

        lock.lock()

        // Don't double-watch
        if sources[path] != nil {
            lock.unlock()
            return
        }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            lock.unlock()
            return
        }

        fileDescriptors[path] = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let suppressed = self.isSuppressed
            let handler = self.changeHandler
            let writeTS = self.lastWriteTimestamp
            self.lock.unlock()

            // Ignore events within the suppression window of a self-initiated write
            if suppressed { return }
            if let writeTS, Date().timeIntervalSince(writeTS) < Self.writeTimestampWindow {
                return
            }

            handler?(url)
        }

        source.setCancelHandler {
            close(fd)
        }

        sources[path] = source
        lock.unlock()

        source.resume()
    }

    /// Stop watching a specific file URL.
    func stopWatching(url: URL) {
        let path = url.resolvingSymlinksInPath().path
        lock.lock()
        let source = sources.removeValue(forKey: path)
        fileDescriptors.removeValue(forKey: path)
        lock.unlock()
        source?.cancel()
    }

    /// Stop watching all files.
    func stopAll() {
        lock.lock()
        let allSources = Array(sources.values)
        sources.removeAll()
        fileDescriptors.removeAll()
        lock.unlock()
        for source in allSources {
            source.cancel()
        }
    }

    /// Suppress notifications temporarily (e.g., during own saves).
    func suppress() {
        lock.lock()
        isSuppressed = true
        lock.unlock()
    }

    /// Resume notifications after suppression.
    func unsuppress() {
        lock.lock()
        isSuppressed = false
        lock.unlock()
    }

    /// Stop watching and re-watch a URL (e.g., after volume remount) (BL-010).
    func reconnect(url: URL) {
        stopWatching(url: url)
        watch(url: url)
    }

    /// Legacy delay kept for API compatibility; the write-timestamp window is the primary guard.
    static let suppressRecoveryDelay: TimeInterval = 0.05

    /// Window (in seconds) after a self-initiated write during which FS events are ignored.
    /// 500ms accommodates slow/network/encrypted volumes where events arrive late.
    static let writeTimestampWindow: TimeInterval = 0.5

    /// Suppress notifications, run an action, then unsuppress after the recovery delay.
    /// Records a write timestamp so late-arriving FS events are also ignored.
    func suppressDuring(_ action: () throws -> Void) rethrows {
        suppress()
        lock.lock()
        lastWriteTimestamp = Date()
        lock.unlock()
        do {
            try action()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.suppressRecoveryDelay) { [self] in
                unsuppress()
            }
        } catch {
            unsuppress()
            throw error
        }
    }

    /// Whether a URL is currently being watched.
    func isWatching(url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        lock.lock()
        let result = sources[path] != nil
        lock.unlock()
        return result
    }

    /// Number of files currently watched.
    var watchCount: Int {
        lock.lock()
        let count = sources.count
        lock.unlock()
        return count
    }
}
