import SwiftUI
import Combine

struct ContentView: View {
    @State private var appState = AppState()
    @State private var toastManager = ToastManager()
    @State private var settings = AppSettings()
    @State private var confirmationService = ConfirmationService()
    @State private var showQuitModal = false

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .fileSelection:
                FileSelectionView()
            case .comparison:
                ComparisonView {
                    appState.resetToFileSelection()
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .toastOverlay(manager: toastManager)
        .decisionToastOverlay(service: confirmationService)
        .preferredColorScheme(settings.theme.colorScheme)
        .environment(appState)
        .environment(toastManager)
        .environment(settings)
        .environment(confirmationService)
        .onAppear {
            // Wire AppDelegate → AppState for quit guard
            AppDelegate.shared?.appState = appState

            // Register AppDelegate as window delegate for close-button guard
            DispatchQueue.main.async {
                if let window = NSApplication.shared.windows.first {
                    window.delegate = AppDelegate.shared
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.quitRequestedNotification)) { _ in
            showQuitModal = true
        }
        .alert("Unsaved Changes", isPresented: $showQuitModal) {
            Button("Save All & Quit") {
                NotificationCenter.default.post(name: .dotEditSaveAllAndQuit, object: nil)
            }
            Button("Discard & Quit", role: .destructive) {
                appState.hasUnsavedChanges = false
                AppDelegate.shared?.isQuitting = true
                NSApplication.shared.terminate(nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Quit anyway?")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let dotEditSaveAllAndQuit = Notification.Name("DotEditSaveAllAndQuit")
}

#Preview {
    ContentView()
}
