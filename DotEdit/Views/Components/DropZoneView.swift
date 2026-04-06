import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    let selectedURL: URL?
    let onDrop: (URL) -> Void
    let onBrowse: () -> Void
    var onDropError: ((String) -> Void)?

    @State private var isTargeted = false
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 28))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)

            Text("Drop .env here or click to browse")
                .font(Theme.monoFont(size: 13))
                .foregroundStyle(isTargeted ? .primary : .secondary)

            Text("(*.env*)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.5, dash: [6, 4])
                )
        )
        .onTapGesture { onBrowse() }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .onDisappear {
            if isHovering {
                NSCursor.pop()
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                DispatchQueue.main.async {
                    onDropError?("Could not read dropped file")
                }
                return
            }
            DispatchQueue.main.async {
                onDrop(url)
            }
        }
        return true
    }
}

#Preview {
    HStack(spacing: 20) {
        DropZoneView(selectedURL: nil, onDrop: { _ in }, onBrowse: {}, onDropError: { _ in })
        DropZoneView(selectedURL: URL(fileURLWithPath: "/tmp/.env"), onDrop: { _ in }, onBrowse: {}, onDropError: { _ in })
    }
    .padding()
    .frame(width: 500, height: 200)
}
