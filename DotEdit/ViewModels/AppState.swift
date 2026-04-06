import SwiftUI

@Observable
final class AppState {
    enum Screen {
        case fileSelection
        case comparison
    }

    var currentScreen: Screen = .fileSelection

    // File selection state
    var leftFileURL: URL?
    var rightFileURL: URL?
    var leftEnvFile: EnvFile?
    var rightEnvFile: EnvFile?

    /// Whether any panel has unsaved changes — used by AppDelegate for quit guard.
    var hasUnsavedChanges: Bool = false

    func navigateTo(_ screen: Screen) {
        currentScreen = screen
    }

    /// Reset file selections and return to file selection screen.
    func resetToFileSelection() {
        leftFileURL = nil
        rightFileURL = nil
        leftEnvFile = nil
        rightEnvFile = nil
        hasUnsavedChanges = false
        currentScreen = .fileSelection
    }
}
