import SwiftUI

struct ToastView: View {
    let toast: ToastManager.Toast
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.severity.iconName)
                .foregroundStyle(.white)

            Text(toast.message)
                .font(.system(.body))
                .foregroundStyle(.white)
                .lineLimit(2)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(toast.severity.color.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

/// Modifier that overlays toast notifications at the bottom-center of the view.
struct ToastOverlayModifier: ViewModifier {
    let toastManager: ToastManager

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = toastManager.currentToast {
                    ToastView(toast: toast) {
                        toastManager.dismiss()
                    }
                    .padding(.bottom, 40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: toastManager.currentToast)
                }
            }
    }
}

extension View {
    func toastOverlay(manager: ToastManager) -> some View {
        modifier(ToastOverlayModifier(toastManager: manager))
    }
}

#Preview {
    VStack {
        Text("Content")
    }
    .frame(width: 600, height: 400)
    .overlay(alignment: .bottom) {
        ToastView(toast: .init(message: "File saved successfully", severity: .success)) {}
            .padding(.bottom, 40)
    }
}
