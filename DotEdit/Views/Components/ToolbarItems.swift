import SwiftUI

// MARK: - ToolbarIcon

/// Flat icon button for toolbar — no chrome at rest, subtle highlight on hover.
/// Set `isCircle: true` for accent-filled circle style (back button).
struct ToolbarIcon: View {
    let icon: String
    var label: String?
    var isToggled: Bool = false
    var isCircle: Bool = false
    var action: () -> Void
    var help: String = ""

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            if isCircle {
                circleContent
            } else {
                flatContent
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(help)
    }

    // MARK: - Circle variant (back button)

    private var circleContent: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(Color.accentColor)
            )
            .opacity(isHovered ? 0.85 : 1.0)
    }

    // MARK: - Flat variant (default)

    private var flatContent: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
            if let label {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .foregroundStyle(isToggled ? Color.accentColor : .primary)
        .fixedSize()
        .frame(height: 28)
        .padding(.horizontal, label != nil ? 8 : 4)
        .frame(minWidth: 32)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
        )
    }

    private var backgroundColor: Color {
        if isToggled && isHovered {
            return Color.accentColor.opacity(0.18)
        }
        if isToggled {
            return Color.accentColor.opacity(0.12)
        }
        if isHovered {
            return Color.primary.opacity(0.06)
        }
        return .clear
    }
}

// MARK: - ToolbarDropdown

/// Flat menu button for toolbar — icon + label + chevron, no chrome.
struct ToolbarDropdown<MenuContent: View>: View {
    let icon: String
    var label: String?
    var help: String = ""
    @ViewBuilder let menuContent: () -> MenuContent

    @State private var isHovered = false

    var body: some View {
        Menu {
            menuContent()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                if let label {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.primary)
            .fixedSize()
            .frame(height: 28)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help(help)
    }
}

// MARK: - ToolbarSegment

/// Two-option segmented picker — the only bordered toolbar element.
struct ToolbarSegment: View {
    let leftLabel: String
    let rightLabel: String
    let isLeftActive: Bool
    var leftHelp: String = ""
    var rightHelp: String = ""
    var onLeft: () -> Void
    var onRight: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            segmentButton(label: leftLabel, isActive: isLeftActive, help: leftHelp, action: onLeft)
            segmentButton(label: rightLabel, isActive: !isLeftActive, help: rightHelp, action: onRight)
        }
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }

    private func segmentButton(label: String, isActive: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isActive ? Color.accentColor.opacity(0.12) : .clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - ToolbarSpacer

/// Explicit whitespace gap between logical toolbar groups.
struct ToolbarSpacer: View {
    var body: some View {
        Color.clear.frame(width: 20)
    }
}
