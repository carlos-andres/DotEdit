import SwiftUI

/// Top toolbar with flat icon buttons, segmented control, and whitespace grouping.
/// Layout: (←)  Reorganize▾ Dedup▾ Comments▾ Collapse  [Align|Sequential] IgnoreCase  wrap # aA12▾  ↻ ⚙ ?
struct ToolbarView: View {
    let isCollapsed: Bool
    let isVisualReorgActive: Bool
    let isReorgPreviewActive: Bool
    let caseInsensitive: Bool
    let sequentialDiff: Bool
    let wordWrap: Bool
    let showLineNumbers: Bool
    let fontSize: CGFloat
    let areCommentsHidden: Bool

    var onBack: () -> Void
    var onToggleVisualReorg: () -> Void
    var onReorganizePreview: (Bool) -> Void  // Bool = hideComments
    var onReorganizeApply: (PanelSide?, Bool) -> Void  // PanelSide? = scope, Bool = stripComments
    var onClearPreview: () -> Void
    var onDedup: (PanelSide?) -> Void
    var onToggleComments: () -> Void
    var onRemoveComments: () -> Void
    var onToggleCollapse: () -> Void
    var onReload: () -> Void
    var onToggleCaseInsensitive: () -> Void
    var onToggleSequentialDiff: () -> Void
    var onToggleWordWrap: () -> Void
    var onToggleLineNumbers: () -> Void
    var onSetFontSize: (CGFloat) -> Void
    var onShowSettings: () -> Void
    var onShowHelp: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // 1. Back — accent circle
            ToolbarIcon(
                icon: "chevron.left",
                isCircle: true,
                action: onBack,
                help: "Go back to file selection"
            )

            ToolbarSpacer()

            // 2. Operations group
            ToolbarDropdown(
                icon: "arrow.up.arrow.down.circle",
                label: isReorgPreviewActive ? "Reorganize ✦" : "Reorganize",
                help: "Reorganize keys by prefix group"
            ) {
                if isReorgPreviewActive {
                    Button("Clear Preview") { onClearPreview() }
                    Divider()
                }

                Text("Preview").font(.caption2).foregroundStyle(.secondary)
                Button("Both Panels") { onReorganizePreview(false) }
                Button("Both & Hide Comments") { onReorganizePreview(true) }

                Divider()

                Text("Apply").font(.caption2).foregroundStyle(.secondary)
                Button("Left Panel") { onReorganizeApply(.left, false) }
                Button("Right Panel") { onReorganizeApply(.right, false) }
                Button("Both Panels") { onReorganizeApply(nil, false) }
                Button("Both & Remove Comments") { onReorganizeApply(nil, true) }
            }

            ToolbarDropdown(
                icon: "minus.circle",
                label: "Dedup",
                help: "Remove duplicate keys"
            ) {
                Button("Left Panel") { onDedup(.left) }
                Button("Right Panel") { onDedup(.right) }
                Divider()
                Button("Both Panels") { onDedup(nil) }
            }

            ToolbarDropdown(
                icon: "number.square",
                label: areCommentsHidden ? "Comments ✦" : "Comments",
                help: "Comment visibility"
            ) {
                Button(areCommentsHidden ? "Show" : "Hide") { onToggleComments() }
                Divider()
                Button("Remove All") { onRemoveComments() }
            }

            ToolbarIcon(
                icon: isCollapsed ? "eye" : "eye.slash",
                label: isCollapsed ? "Show All" : "Collapse",
                isToggled: isCollapsed,
                action: onToggleCollapse,
                help: isCollapsed ? "Show all rows" : "Hide identical rows"
            )

            ToolbarSpacer()

            // 3. Diff modes group
            ToolbarSegment(
                leftLabel: "Align",
                rightLabel: "Sequential",
                isLeftActive: isVisualReorgActive,
                leftHelp: isVisualReorgActive ? "Return to original file order" : "Align keys by prefix across panels",
                rightHelp: "Position-based diff (line-by-line)",
                onLeft: onToggleVisualReorg,
                onRight: onToggleSequentialDiff
            )

            ToolbarIcon(
                icon: caseInsensitive ? "checkmark.square.fill" : "square",
                label: "Ignore Case",
                isToggled: caseInsensitive,
                action: onToggleCaseInsensitive,
                help: "Case-insensitive key matching"
            )

            ToolbarSpacer()

            // 4. Display group
            ToolbarIcon(
                icon: "text.word.spacing",
                label: "wrap",
                isToggled: wordWrap,
                action: onToggleWordWrap,
                help: "Toggle word wrap"
            )

            ToolbarIcon(
                icon: "number",
                isToggled: showLineNumbers,
                action: onToggleLineNumbers,
                help: "Toggle line numbers"
            )

            ToolbarDropdown(
                icon: "textformat.size",
                label: "\(Int(fontSize))",
                help: "Font size (\u{2318}+/\u{2318}-/\u{2318}0)"
            ) {
                ForEach(Array(stride(from: Int(AppSettings.fontSizeRange.lowerBound),
                                     through: Int(AppSettings.fontSizeRange.upperBound),
                                     by: 1)), id: \.self) { size in
                    Button {
                        onSetFontSize(CGFloat(size))
                    } label: {
                        HStack {
                            Text("\(size)")
                            if CGFloat(size) == fontSize {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Spacer()

            // 5. Utilities group (right-aligned)
            ToolbarIcon(
                icon: "arrow.clockwise",
                action: onReload,
                help: "Reload files from disk (\u{2318}R)"
            )

            ToolbarIcon(
                icon: "gearshape",
                action: onShowSettings,
                help: "Settings"
            )

            ToolbarIcon(
                icon: "questionmark.circle",
                action: onShowHelp,
                help: "Help (\u{2318}/)"
            )
        }
        .padding(.horizontal, 16)
        .frame(height: Theme.toolbarHeight)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
