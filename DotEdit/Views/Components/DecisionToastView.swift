import SwiftUI

/// Enhanced toast with title, message, and confirm/cancel buttons.
/// Slides up from bottom and stays until user acts. Used for operation confirmations
/// (reorg, consolidate) — not for system-level alerts (unsaved/quit).
struct DecisionToastView: View {
    let decision: ConfirmationService.Decision
    var onConfirm: () -> Void
    var onCancel: () -> Void

    private var backgroundColor: Color { .blue }

    var body: some View {
        VStack(spacing: 10) {
            // Title + close button
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.white)
                Text(decision.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()

                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Message
            Text(decision.message)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Buttons
            HStack(spacing: 10) {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.15))
                )

                Button(decision.confirmLabel) {
                    onConfirm()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor)
                )
            }
        }
        .padding(16)
        .frame(maxWidth: 400)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColor.opacity(0.9))
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        )
    }
}

/// Modifier that overlays decision toast at the bottom-center of the view.
struct DecisionToastOverlayModifier: ViewModifier {
    let confirmationService: ConfirmationService

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let decision = confirmationService.currentDecision {
                    DecisionToastView(
                        decision: decision,
                        onConfirm: { confirmationService.confirm() },
                        onCancel: { confirmationService.dismiss() }
                    )
                    .padding(.bottom, 48)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: confirmationService.currentDecision?.id)
                    .onKeyPress(.escape) {
                        confirmationService.dismiss()
                        return .handled
                    }
                }
            }
    }
}

extension View {
    func decisionToastOverlay(service: ConfirmationService) -> some View {
        modifier(DecisionToastOverlayModifier(confirmationService: service))
    }
}
