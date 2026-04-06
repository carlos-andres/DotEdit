import SwiftUI

/// Compact action bar with pillow-style Save / Undo / Redo buttons for a single panel.
struct PanelActionBarView: View {
    let isDirty: Bool
    let undoManager: UndoManager
    let onSave: () -> Void
    var onSearch: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            PillButton(
                icon: "square.and.arrow.down",
                isActive: isDirty,
                isAccent: true,
                action: onSave,
                help: "Save"
            )
            PillButton(
                icon: "arrow.uturn.backward",
                isActive: undoManager.canUndo,
                action: { undoManager.undo() },
                help: "Undo"
            )
            PillButton(
                icon: "arrow.uturn.forward",
                isActive: undoManager.canRedo,
                action: { undoManager.redo() },
                help: "Redo"
            )

            if let onSearch {
                PillButton(
                    icon: "magnifyingglass",
                    isActive: true,
                    action: onSearch,
                    help: "Search (\u{2318}F)"
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Theme.actionBarHeight)
        .background(.bar)
    }
}
