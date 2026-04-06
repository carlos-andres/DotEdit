import SwiftUI

@MainActor
@Observable
final class ToastManager {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let severity: Severity

        enum Severity {
            case info, success, warning, error

            var color: Color {
                switch self {
                case .info: .blue
                case .success: .green
                case .warning: .orange
                case .error: .red
                }
            }

            var iconName: String {
                switch self {
                case .info: "info.circle.fill"
                case .success: "checkmark.circle.fill"
                case .warning: "exclamationmark.triangle.fill"
                case .error: "xmark.circle.fill"
                }
            }
        }

        static func == (lhs: Toast, rhs: Toast) -> Bool {
            lhs.id == rhs.id
        }
    }

    var currentToast: Toast?

    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, severity: Toast.Severity = .info) {
        dismissTask?.cancel()
        currentToast = Toast(message: message, severity: severity)
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                currentToast = nil
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.3)) {
            currentToast = nil
        }
    }
}
