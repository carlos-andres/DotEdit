import SwiftUI

struct FilePanelView: View {
    let label: String
    @Binding var selectedURL: URL?
    let recentFilesManager: RecentFilesManager
    let onValidationError: (String) -> Void
    var alignment: HorizontalAlignment = .leading

    @State private var recentFiles: [URL] = []

    var body: some View {
        VStack(alignment: alignment, spacing: 12) {
            // Panel label
            Text(label)
                .font(.headline)
                .foregroundStyle(.secondary)

            // Drop zone (click to browse, or drag to drop)
            DropZoneView(selectedURL: selectedURL, onDrop: { url in
                validateAndSelect(url)
            }, onBrowse: {
                if let url = EnvFilePanel.open() {
                    validateAndSelect(url)
                }
            }, onDropError: { message in
                onValidationError(message)
            })

            // Selected file path
            if let url = selectedURL {
                selectedFileRow(url)
            }

            // Recent files
            if !recentFiles.isEmpty {
                recentFilesSection
            }

            Spacer()
        }
        .padding()
        .onAppear {
            refreshRecents()
        }
    }

    // MARK: - Selected File Row

    @ViewBuilder
    private func selectedFileRow(_ url: URL) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(Color.accentColor)
                .font(.caption)

            Text(url.lastPathComponent)
                .font(Theme.monoFont(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                selectedURL = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help(url.path)
    }

    // MARK: - Recent Files

    @ViewBuilder
    private var recentFilesSection: some View {
        VStack(alignment: alignment, spacing: 6) {
            HStack {
                Text("Recent")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
            }

            ForEach(recentFiles, id: \.self) { url in
                Button {
                    validateAndSelect(url)
                } label: {
                    HStack(spacing: 4) {
                        if alignment == .leading {
                            Text("\u{2022}")
                                .foregroundStyle(Color.accentColor)
                        }
                        (Text("../\(clampedParent(url))/")
                            .font(Theme.monoFont(size: 11))
                            .foregroundStyle(.secondary)
                        + Text(url.lastPathComponent)
                            .font(Theme.monoFont(size: 11))
                            .foregroundStyle(.primary))
                        .lineLimit(1)
                        .truncationMode(.head)
                        if alignment == .trailing {
                            Text("\u{2022}")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .help(url.path)
            }

            Button("Clear recents") {
                recentFilesManager.clearRecents()
                refreshRecents()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func validateAndSelect(_ url: URL) {
        let result = FileValidator.validate(url: url)
        guard result.isValid else {
            onValidationError(result.reason ?? "Invalid file")
            return
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            onValidationError("File not found: \(url.path)")
            return
        }

        selectedURL = url
        recentFilesManager.addFile(url: url)
        refreshRecents()
    }

    private func refreshRecents() {
        recentFiles = recentFilesManager.recentFiles()
    }

    /// Parent folder name for clamped path display.
    private func clampedParent(_ url: URL) -> String {
        url.deletingLastPathComponent().lastPathComponent
    }
}

#Preview {
    @Previewable @State var url: URL? = nil
    FilePanelView(
        label: "Left File",
        selectedURL: $url,
        recentFilesManager: RecentFilesManager(),
        onValidationError: { _ in }
    )
    .frame(width: 300, height: 500)
}
