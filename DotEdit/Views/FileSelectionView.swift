import SwiftUI

struct FileSelectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    @Environment(ToastManager.self) private var toastManager

    @State private var leftURL: URL?
    @State private var rightURL: URL?
    @State private var showHelp = false
    @State private var showSettings = false

    private let leftRecents = RecentFilesManager(key: "recentEnvFiles.left")
    private let rightRecents = RecentFilesManager(key: "recentEnvFiles.right")

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Two-panel layout
                HStack(alignment: .top, spacing: 0) {
                    FilePanelView(
                        label: "Left File",
                        selectedURL: $leftURL,
                        recentFilesManager: leftRecents,
                        onValidationError: { message in
                            toastManager.show(message, severity: .error)
                        }
                    )

                    Divider()

                    FilePanelView(
                        label: "Right File",
                        selectedURL: $rightURL,
                        recentFilesManager: rightRecents,
                        onValidationError: { message in
                            toastManager.show(message, severity: .error)
                        },
                        alignment: .trailing
                    )
                }
            }

            // Floating center controls
            VStack(spacing: 12) {
                compareButton
                helpSettingsButtons
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Help & Settings Buttons

    private var helpSettingsButtons: some View {
        VStack(spacing: 8) {
            overlayButton(icon: "gearshape", action: { showSettings = true })
            overlayButton(icon: "questionmark.circle", action: { showHelp = true })
        }
    }

    private func overlayButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    // MARK: - Compare Button

    private var compareButton: some View {
        Button {
            handleCompare()
        } label: {
            Text("Compare")
                .font(Theme.monoFont(size: 14).weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 88, height: 88)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 8, y: 4)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    // MARK: - Compare Validation

    private func handleCompare() {
        // Both files must be selected
        guard let left = leftURL, let right = rightURL else {
            toastManager.show("Please select both files", severity: .warning)
            return
        }

        // Same file check (DEC-020)
        if left.standardizedFileURL == right.standardizedFileURL {
            toastManager.show(
                "Same file selected for both panels. Choose a different file.",
                severity: .warning
            )
            return
        }

        // File existence check
        let fm = FileManager.default
        if !fm.fileExists(atPath: left.path) {
            toastManager.show("File not found: \(left.lastPathComponent)", severity: .error)
            return
        }
        if !fm.fileExists(atPath: right.path) {
            toastManager.show("File not found: \(right.lastPathComponent)", severity: .error)
            return
        }

        // Load files
        do {
            let leftEnv = try FileLoader.load(url: left)
            let rightEnv = try FileLoader.load(url: right)

            appState.leftFileURL = left
            appState.rightFileURL = right
            appState.leftEnvFile = leftEnv
            appState.rightEnvFile = rightEnv
            settings.resetComparisonState() // DEC-042: clean state before each comparison
            appState.navigateTo(.comparison)
        } catch {
            toastManager.show(error.localizedDescription, severity: .error)
        }
    }
}

#Preview {
    ContentView()
}
