import SwiftUI

/// Hidden keyboard shortcut buttons for the comparison view.
/// Extracted from ComparisonView to reduce file size.
struct ComparisonKeyboardShortcuts: ViewModifier {
    var onSaveFocused: () -> Void
    var onSaveAll: () -> Void
    var onReload: () -> Void
    var onSearch: () -> Void
    var onEscape: () -> Void
    var onSetFontSize: (CGFloat) -> Void
    var onShowHelp: () -> Void

    func body(content: Content) -> some View {
        content.background {
            // ⌘S — save focused panel
            Button("") { onSaveFocused() }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()
            // ⌘⌥S — save both panels
            Button("") { onSaveAll() }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .hidden()
            // ⌘R — reload
            Button("") { onReload() }
                .keyboardShortcut("r", modifiers: .command)
                .hidden()
            // ⌘F — search
            Button("") { onSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
            // Esc — close search
            Button("") { onEscape() }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
            // ⌘+ — increase font size
            Button("") { onSetFontSize(1) }
                .keyboardShortcut("+", modifiers: .command)
                .hidden()
            Button("") { onSetFontSize(1) }
                .keyboardShortcut("=", modifiers: .command)
                .hidden()
            // ⌘- — decrease font size
            Button("") { onSetFontSize(-1) }
                .keyboardShortcut("-", modifiers: .command)
                .hidden()
            // ⌘0 — reset font size
            Button("") { onSetFontSize(0) }
                .keyboardShortcut("0", modifiers: .command)
                .hidden()
            // ⌘/ — Help
            Button { onShowHelp() } label: { EmptyView() }
                .keyboardShortcut("/", modifiers: .command)
                .hidden()
        }
    }
}
