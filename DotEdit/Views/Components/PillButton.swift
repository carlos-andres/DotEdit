import SwiftUI

/// Reusable pill-style button with icon, optional label, toggle state, and accent mode.
/// Used in both PanelActionBarView and ToolbarView for consistent styling.
struct PillButton: View {
    let icon: String
    var label: String?
    var isActive: Bool = true
    var isAccent: Bool = false
    var isToggled: Bool = false
    var action: () -> Void
    var help: String = ""

    var body: some View {
        let useAccent = isAccent && isActive
        let useToggle = isToggled && isActive

        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                if let label {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(foregroundColor(useAccent: useAccent, useToggle: useToggle))
            .fixedSize()
            .frame(height: 22)
            .padding(.horizontal, label != nil ? 10 : 2)
            .frame(minWidth: 28)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(useAccent: useAccent, useToggle: useToggle))
                    .shadow(
                        color: shadowColor(useAccent: useAccent),
                        radius: useAccent ? 3 : 2,
                        y: 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(isActive ? 0.2 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isActive)
        .help(help)
    }

    // MARK: - Styling

    private func foregroundColor(useAccent: Bool, useToggle: Bool) -> Color {
        if useAccent { return .white }
        if useToggle { return .accentColor }
        if isActive { return .primary }
        return .secondary.opacity(0.4)
    }

    private func backgroundColor(useAccent: Bool, useToggle: Bool) -> Color {
        if useAccent { return .accentColor }
        if useToggle { return Color.accentColor.opacity(0.15) }
        if isActive { return Color(NSColor.controlBackgroundColor) }
        return Color(NSColor.controlBackgroundColor).opacity(0.5)
    }

    private func shadowColor(useAccent: Bool) -> Color {
        if useAccent { return .accentColor.opacity(0.3) }
        if isActive { return .black.opacity(0.12) }
        return .clear
    }
}

