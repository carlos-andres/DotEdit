import SwiftUI

/// Orange warning banner shown when a file becomes unreachable (BL-010).
/// Appears above diff panels below toolbar.
struct FileInaccessibleBanner: View {
    let side: String
    let filePath: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))

            VStack(alignment: .leading, spacing: 1) {
                Text("\(side) file is unreachable")
                    .font(Theme.monoFont(size: 11).bold())
                    .foregroundStyle(.primary)
                Text("Network volume may be disconnected. Use Save As to save elsewhere.")
                    .font(Theme.monoFont(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
    }
}
