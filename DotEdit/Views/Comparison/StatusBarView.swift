import SwiftUI

/// Bottom status bar showing clamped paths, key counts, and diff summary.
struct StatusBarView: View {
    let leftFile: EnvFile
    let rightFile: EnvFile
    let stats: ComparisonViewModel.DiffStats
    var collapsedCount: Int = 0
    var warningCount: Int = 0
    var onToggleWarnings: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            // Left info
            HStack(spacing: 8) {
                Text(PathClamper.clamp(leftFile.filePath))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(leftFile.filePath)

                Text("\(leftFile.keyCount) keys")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Diff summary (center)
            diffSummary

            Spacer()

            // Right info
            HStack(spacing: 8) {
                Text("\(rightFile.keyCount) keys")
                    .foregroundStyle(.secondary)

                Text(PathClamper.clamp(rightFile.filePath))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(rightFile.filePath)
            }
        }
        .font(Theme.monoFont(size: 10))
        .padding(.horizontal, Theme.rowHorizontalPadding)
        .frame(height: Theme.statusBarHeight)
        .background(.bar)
    }

    @ViewBuilder
    private var diffSummary: some View {
        HStack(spacing: 6) {
            if stats.modified > 0 {
                badge("\(stats.modified)~", color: .blue)
            }
            if stats.leftOnly > 0 {
                badge("\(stats.leftOnly)\u{00AB}", color: .orange)
            }
            if stats.rightOnly > 0 {
                badge("\(stats.rightOnly)\u{00BB}", color: .green)
            }
            if collapsedCount > 0 {
                badge("\(collapsedCount) hidden", color: .gray)
            }
            if warningCount > 0, let onToggle = onToggleWarnings {
                Button {
                    onToggle()
                } label: {
                    badge("⚠ \(warningCount)", color: .orange)
                }
                .buttonStyle(.plain)
            }
            if stats.totalDiffs == 0 {
                Text("Identical")
                    .foregroundStyle(.green)
            }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.monoFont(size: 10))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
    }
}
