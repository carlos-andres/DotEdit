import SwiftUI

/// Manages decision toast confirmations for non-system operations.
/// System-level confirmations (unsaved back, reload, quit, external change) stay as native .alert().
/// Operation confirmations (reorg, consolidate) use DecisionToast via this service.
@MainActor
@Observable
final class ConfirmationService {

    struct Decision: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let confirmLabel: String
        let isDestructive: Bool
        let onConfirm: () -> Void
    }

    var currentDecision: Decision?

    /// Request a decision toast with confirm/cancel buttons.
    func requestDecision(
        title: String,
        message: String,
        confirmLabel: String = "Confirm",
        isDestructive: Bool = false,
        onConfirm: @escaping () -> Void
    ) {
        currentDecision = Decision(
            title: title,
            message: message,
            confirmLabel: confirmLabel,
            isDestructive: isDestructive,
            onConfirm: onConfirm
        )
    }

    func confirm() {
        currentDecision?.onConfirm()
        dismiss()
    }

    func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) {
            currentDecision = nil
        }
    }
}
