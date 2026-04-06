import AppKit

/// Presents an NSOpenPanel pre-configured for .env file browsing.
///
/// Unlike SwiftUI's `.fileImporter()`, this panel:
/// - Shows hidden files by default (`showsHiddenFiles = true`)
/// - Grays out non-.env files using `FileValidator`
enum EnvFilePanel {

    /// Opens a modal NSSavePanel pre-populated with the given filename.
    /// Returns the chosen URL, or `nil` if cancelled.
    @MainActor
    static func saveAs(suggestedName: String, message: String = "Save As") -> URL? {
        let panel = NSSavePanel()
        panel.showsHiddenFiles = true
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        panel.message = message
        panel.prompt = "Save"

        let response = panel.runModal()
        guard response == .OK else { return nil }
        return panel.url
    }

    /// Opens a modal NSOpenPanel and returns the selected URL, or `nil` if cancelled.
    @MainActor
    static func open() -> URL? {
        let panel = NSOpenPanel()
        panel.showsHiddenFiles = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.message = "Select a .env file"
        panel.prompt = "Select"

        let delegate = EnvPanelDelegate()
        panel.delegate = delegate

        let response = panel.runModal()
        guard response == .OK else { return nil }
        return panel.url
    }
}

// MARK: - Delegate

/// Enables directories for navigation but grays out non-.env files.
private final class EnvPanelDelegate: NSObject, NSOpenSavePanelDelegate {

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        // Always enable directories for navigation
        if exists && isDirectory.boolValue {
            return true
        }

        // Enable only valid .env files
        return FileValidator.validate(url: url).isValid
    }
}
