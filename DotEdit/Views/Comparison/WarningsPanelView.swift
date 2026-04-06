import SwiftUI

/// Standalone warnings panel extracted from ComparisonView.
struct WarningsPanelView: View {
    var vm: ComparisonViewModel
    @Binding var showWarningsPanel: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            warningsList
        }
        .padding(.bottom, 4)
        .background(.bar)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 10))
            Text("Warnings (\(vm.warningCount))")
                .font(Theme.monoFont(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                showWarningsPanel = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    // MARK: - Warnings List

    private var warningsList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 1) {
                // Left file warnings
                let leftWarnings = vm.leftFile.allWarnings
                if !leftWarnings.isEmpty {
                    Text("Left: \(PathClamper.clamp(vm.leftFile.filePath))")
                        .font(Theme.monoFont(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                    ForEach(leftWarnings) { warning in
                        warningRow(warning)
                    }
                }

                // Right file warnings
                let rightWarnings = vm.rightFile.allWarnings
                if !rightWarnings.isEmpty {
                    Text("Right: \(PathClamper.clamp(vm.rightFile.filePath))")
                        .font(Theme.monoFont(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 2)
                    ForEach(rightWarnings) { warning in
                        warningRow(warning)
                    }
                }
            }
        }
        .frame(maxHeight: 120)
    }

    // MARK: - Warning Row

    private func warningRow(_ warning: EnvFile.FileWarning) -> some View {
        Button {
            // Jump to the warning's line
            if let lineNum = warning.lineNumber {
                if let row = vm.rows.first(where: { row in
                    row.leftEntry?.lineNumber == lineNum || row.rightEntry?.lineNumber == lineNum
                }) {
                    vm.scrollTarget = row.id
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(warning.type.rawValue)
                    .font(Theme.monoFont(size: 9))
                    .foregroundStyle(.orange)
                    .frame(width: 90, alignment: .leading)

                Text(warning.message)
                    .font(Theme.monoFont(size: 10))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                if let line = warning.lineNumber {
                    Text("L\(line)")
                        .font(Theme.monoFont(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
