import SwiftUI

/// Sheet showing a diff summary when a file is changed externally while dirty.
/// Displays stats pills, scrollable change list, and Reload/Keep buttons (BL-004).
struct ExternalChangeDiffSheet: View {
    let sideLabel: String
    let stats: ComparisonViewModel.DiffStats
    let changes: [DiffResult]
    let onReload: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Stats pills
            statsPills
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider()

            // Change list
            if changes.isEmpty {
                Spacer()
                Text("No differences detected")
                    .font(Theme.monoFont(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                changeList
            }

            Divider()

            // Action buttons
            actionButtons
                .padding(16)
        }
        .frame(width: 500, height: 400)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("\(sideLabel) File Changed Externally")
                .font(.headline)
            Spacer()
        }
        .padding(16)
    }

    // MARK: - Stats Pills

    private var statsPills: some View {
        HStack(spacing: 8) {
            if stats.modified > 0 {
                statsPill("\(stats.modified) modified", color: .blue)
            }
            if stats.leftOnly > 0 {
                statsPill("\(stats.leftOnly) removed", color: .orange)
            }
            if stats.rightOnly > 0 {
                statsPill("\(stats.rightOnly) added", color: .green)
            }
            if stats.totalDiffs == 0 {
                statsPill("Identical", color: .gray)
            }
            Spacer()
            if changes.count >= 50 {
                Text("showing first 50")
                    .font(Theme.monoFont(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statsPill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(Theme.monoFont(size: 11))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Change List

    private var changeList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 0) {
                ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                    changeRow(change)
                    Divider().opacity(0.3)
                }
            }
        }
    }

    private func changeRow(_ change: DiffResult) -> some View {
        HStack(spacing: 8) {
            categoryBadge(change.category)

            VStack(alignment: .leading, spacing: 2) {
                // Key name
                Text(changeKey(change))
                    .font(Theme.monoFont(size: 12).bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Value changes
                if change.category == .modified {
                    HStack(spacing: 4) {
                        Text(truncateValue(change.leftEntry?.value))
                            .font(Theme.monoFont(size: 10))
                            .foregroundStyle(.red.opacity(0.8))
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Text(truncateValue(change.rightEntry?.value))
                            .font(Theme.monoFont(size: 10))
                            .foregroundStyle(.green.opacity(0.8))
                            .lineLimit(1)
                    }
                } else if change.category == .leftOnly {
                    Text(truncateValue(change.leftEntry?.value))
                        .font(Theme.monoFont(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if change.category == .rightOnly {
                    Text(truncateValue(change.rightEntry?.value))
                        .font(Theme.monoFont(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func categoryBadge(_ category: DiffResult.Category) -> some View {
        let (label, color): (String, Color) = switch category {
        case .modified: ("MOD", .blue)
        case .leftOnly: ("DEL", .orange)
        case .rightOnly: ("ADD", .green)
        case .equal: ("EQ", .gray)
        }

        return Text(label)
            .font(Theme.monoFont(size: 9).bold())
            .foregroundStyle(color)
            .frame(width: 32)
    }

    private func changeKey(_ change: DiffResult) -> String {
        change.leftEntry?.key ?? change.rightEntry?.key ?? "(unknown)"
    }

    private func truncateValue(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "(empty)" }
        if value.count > 80 {
            return String(value.prefix(77)) + "..."
        }
        return value
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack {
            Spacer()

            Button("Keep My Changes") {
                onKeep()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button("Reload from Disk") {
                onReload()
            }
            .keyboardShortcut(.return, modifiers: [])
            .buttonStyle(.borderedProminent)
        }
    }
}
