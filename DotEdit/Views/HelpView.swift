import SwiftUI

/// Help sheet showing keyboard shortcuts, gutter legend, and tips.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Help")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    // MARK: - Top: 2-column card layout
                    HStack(alignment: .top, spacing: 14) {
                        // Left card: Toolbar
                        card(stretch: true) {
                            sectionLabel("Toolbar")
                            toolRow("checkmark.square", "Align", "Cross-panel key alignment (display only)")
                            toolRow("arrow.up.arrow.down.circle", "Reorganize", "Preview or Apply: group & sort by prefix")
                            toolRow("minus.circle", "Dedup", "Remove duplicate keys")
                            toolRow("number.square", "Comments", "Hide or remove comment/blank lines")
                            toolRow("eye", "Collapse", "Hide identical rows")
                            toolRow("checkmark.square", "Ignore Case", "Case-insensitive key matching")
                            toolRow("checkmark.square", "Sequential", "Position-based diff (line-by-line)")
                            toolRow("textformat.size", "Font Size", "Adjust editor font size (\u{2318}+/\u{2318}-)")
                            toolRow("arrow.clockwise", "Reload", "Reload from disk")
                            toolRow("gearshape", "Settings", "Preferences & options")
                        }

                        // Right column: 2 stacked cards
                        VStack(spacing: 14) {
                            // Keyboard Shortcuts card
                            card {
                                sectionLabel("Keyboard Shortcuts")
                                shortcutRow("⌘S", "Save panel")
                                shortcutRow("⌘⌥S", "Save all")
                                shortcutRow("⌘R", "Reload")
                                shortcutRow("⌘F", "Search")
                                shortcutRow("⌘+/⌘-", "Font size")
                                shortcutRow("⌘0", "Reset font")
                                shortcutRow("Esc", "Cancel")
                                shortcutRow("⌘Q", "Quit")
                                shortcutRow("⌘/", "Help")
                            }

                            // Gutter Symbols card
                            card {
                                sectionLabel("Gutter Symbols")
                                symbolRow("»", "Copy to right", Color.blue)
                                symbolRow("«", "Copy to left", Color.orange)
                                symbolRow("=", "Equal", Color.secondary)
                                symbolRow("~", "Modified", Color.blue)

                                Text("Left-only → » right  ·  Right-only → « left")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .frame(minHeight: 0)

                    // MARK: - Tips card (full width)
                    card {
                        sectionLabel("Tips")
                        tipRow("Click any row to edit inline")
                        tipRow("Drag the center divider to resize panels")
                        tipRow("Search auto-expands collapsed rows")
                        tipRow("Hover clamped paths for full file path")
                        tipRow("Warnings badge in status bar shows file issues")
                        tipRow("Transfer mode (Settings) controls Full Line vs Value Only")
                        tipRow("Preview (see) → Apply (rewrite): two modes of reorganization")
                    }
                }
                .padding(20)
            }
        }
        // 80%×76% of min resolution (1024×768) — matches SettingsView
        .frame(width: 820, height: 580)
    }

    // MARK: - Card Container

    private func card<Content: View>(stretch: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: stretch ? .infinity : nil, alignment: .topLeading)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Section Label

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .padding(.bottom, 10)
    }

    // MARK: - Shortcut Row

    private func shortcutRow(_ key: String, _ description: String) -> some View {
        HStack(spacing: 0) {
            Text(key)
                .font(Theme.monoFont(size: 11))
                .foregroundStyle(Color.accentColor)
                .frame(width: 52, alignment: .trailing)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
            Spacer()
        }
        .padding(.vertical, 3)
    }

    // MARK: - Symbol Row

    private func symbolRow(_ symbol: String, _ description: String, _ color: Color) -> some View {
        HStack(spacing: 0) {
            Text(symbol)
                .font(Theme.monoFont(size: 14))
                .foregroundStyle(color)
                .frame(width: 52, alignment: .center)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
            Spacer()
        }
        .padding(.vertical, 3)
    }

    // MARK: - Tool Row

    private func toolRow(_ icon: String, _ name: String, _ desc: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Tip Row

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(Color.accentColor.opacity(0.5))
                .frame(width: 4, height: 4)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
