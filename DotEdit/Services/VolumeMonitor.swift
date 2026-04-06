import Foundation
import AppKit

/// Monitors file accessibility for network volume disconnects (BL-010).
/// Listens to NSWorkspace mount/unmount notifications and performs periodic
/// accessibility checks every 30 seconds.
@MainActor
final class VolumeMonitor {

    // MARK: - Types

    typealias AccessibilityHandler = (URL, Bool) -> Void

    // MARK: - State

    private var monitoredURLs: Set<URL> = []
    private var accessibilityState: [URL: Bool] = [:]
    private var handler: AccessibilityHandler?
    private var timer: Timer?
    private var mountObserver: NSObjectProtocol?
    private var unmountObserver: NSObjectProtocol?

    /// Check interval in seconds.
    let checkInterval: TimeInterval

    // MARK: - Init

    init(checkInterval: TimeInterval = 30) {
        self.checkInterval = checkInterval
    }

    // MARK: - Public API

    /// Set the accessibility change handler.
    func setHandler(_ handler: @escaping AccessibilityHandler) {
        self.handler = handler
    }

    /// Register a URL for monitoring.
    func monitor(url: URL) {
        let resolved = url.resolvingSymlinksInPath()
        monitoredURLs.insert(resolved)
        let accessible = FileManager.default.fileExists(atPath: resolved.path)
        accessibilityState[resolved] = accessible
    }

    /// Remove a URL from monitoring.
    func unmonitor(url: URL) {
        let resolved = url.resolvingSymlinksInPath()
        monitoredURLs.remove(resolved)
        accessibilityState.removeValue(forKey: resolved)
    }

    /// Start periodic checks and volume notifications.
    func start() {
        // Volume unmount notification
        unmountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract Sendable data before crossing isolation boundary
            let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            Task { @MainActor [weak self] in
                guard let volumeURL else { return }
                self?.handleVolumeEvent(volumeURL: volumeURL, isMounting: false)
            }
        }

        // Volume mount notification
        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let volumeURL = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            Task { @MainActor [weak self] in
                guard let volumeURL else { return }
                self?.handleVolumeEvent(volumeURL: volumeURL, isMounting: true)
            }
        }

        // Periodic check timer
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkAccessibility()
            }
        }
    }

    /// Stop all monitoring.
    func stop() {
        timer?.invalidate()
        timer = nil

        if let observer = unmountObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            unmountObserver = nil
        }
        if let observer = mountObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            mountObserver = nil
        }
    }

    /// Check if a URL is currently accessible.
    func isAccessible(url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        return accessibilityState[resolved] ?? true
    }

    /// Force an immediate accessibility check (useful for tests).
    func checkAccessibility() {
        let fm = FileManager.default
        for url in monitoredURLs {
            let nowAccessible = fm.fileExists(atPath: url.path)
            let wasAccessible = accessibilityState[url] ?? true

            if nowAccessible != wasAccessible {
                accessibilityState[url] = nowAccessible
                handler?(url, nowAccessible)
            }
        }
    }

    // MARK: - Private

    private func handleVolumeEvent(volumeURL: URL, isMounting: Bool) {
        let volumePath = volumeURL.path

        for url in monitoredURLs {
            if url.path.hasPrefix(volumePath) {
                let nowAccessible: Bool
                if isMounting {
                    nowAccessible = FileManager.default.fileExists(atPath: url.path)
                } else {
                    nowAccessible = false
                }

                let wasAccessible = accessibilityState[url] ?? true
                if nowAccessible != wasAccessible {
                    accessibilityState[url] = nowAccessible
                    handler?(url, nowAccessible)
                }
            }
        }
    }
}
