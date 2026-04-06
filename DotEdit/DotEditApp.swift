import SwiftUI

@main
struct DotEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: Theme.defaultWindowWidth, height: Theme.defaultWindowHeight)
        .windowResizability(.contentMinSize)
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Posted when the user attempts to quit with unsaved changes.
    static let quitRequestedNotification = Notification.Name("DotEditQuitRequested")

    /// Shared reference so AppState can be checked.
    nonisolated(unsafe) static weak var shared: AppDelegate?

    /// Set by ContentView to provide quit-guard state.
    var appState: AppState?

    /// When true, bypass all guards and allow quit/close immediately.
    /// Accessed from both AppKit callbacks and @MainActor SwiftUI code.
    nonisolated(unsafe) var isQuitting = false

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    // MARK: - App Lifecycle

    /// Single-window app: quit when the last window closes.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Dock icon clicked with no visible windows — reopen a window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // WindowGroup will create a new window automatically
            return true
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isQuitting { return .terminateNow }
        guard let appState, appState.hasUnsavedChanges else {
            return .terminateNow
        }
        // Cancel quit, let the UI show a confirmation modal
        NotificationCenter.default.post(name: AppDelegate.quitRequestedNotification, object: nil)
        return .terminateCancel
    }

    // MARK: - Window Close Guard

    /// Intercepts the red close button — guards unsaved changes before window closes.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isQuitting { return true }
        guard let appState, appState.hasUnsavedChanges else {
            return true // No unsaved changes, allow close → triggers app quit
        }
        // Block close, show save modal instead
        NotificationCenter.default.post(name: AppDelegate.quitRequestedNotification, object: nil)
        return false
    }
}
