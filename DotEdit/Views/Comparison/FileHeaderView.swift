import SwiftUI

/// Filename and clamped path displayed above each panel.
/// Shows red ● when panel has unsaved changes.
struct FileHeaderView: View {
    let fileURL: URL?
    let filePath: String
    var isDirty: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Text(filename)
                    .font(Theme.monoFont(size: 12))
                    .fontWeight(.medium)
                    .lineLimit(1)

                if isDirty {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .help("Unsaved changes")
                }

                Spacer()

                Text(clampedPath)
                    .font(Theme.monoFont(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help(filePath)
            }
            .padding(.horizontal, Theme.rowHorizontalPadding)
        }
        .frame(height: Theme.headerHeight)
        .background(.bar)
    }

    private var filename: String {
        fileURL?.lastPathComponent ?? URL(fileURLWithPath: filePath).lastPathComponent
    }

    private var clampedPath: String {
        if let url = fileURL {
            return PathClamper.clamp(url)
        }
        return PathClamper.clamp(filePath)
    }
}
