import SwiftUI

struct WarningModal: View {
    let title: String
    let message: String
    let actions: [ModalAction]

    struct ModalAction: Identifiable {
        let id = UUID()
        let label: String
        let role: ButtonRole?
        let action: () -> Void

        init(_ label: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
            self.label = label
            self.role = role
            self.action = action
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)

                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                ForEach(actions) { action in
                    Button(role: action.role) {
                        action.action()
                    } label: {
                        Text(action.label)
                            .frame(minWidth: 80)
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
    }
}

/// Modifier for presenting a warning modal as a centered overlay with background dimming.
struct WarningModalOverlayModifier: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let actions: [WarningModal.ModalAction]

    func body(content: Content) -> some View {
        content
            .overlay {
                if isPresented {
                    ZStack {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .onTapGesture {} // block background interaction

                        WarningModal(
                            title: title,
                            message: message,
                            actions: actions
                        )
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                    .animation(.easeInOut(duration: 0.2), value: isPresented)
                }
            }
    }
}

extension View {
    func warningModal(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        actions: [WarningModal.ModalAction]
    ) -> some View {
        modifier(WarningModalOverlayModifier(
            isPresented: isPresented,
            title: title,
            message: message,
            actions: actions
        ))
    }
}

#Preview {
    VStack {
        Text("Background Content")
    }
    .frame(width: 600, height: 400)
    .overlay {
        Color.black.opacity(0.4)
        WarningModal(
            title: "Unsaved Changes",
            message: "You have unsaved changes in both panels.\nWhat would you like to do?",
            actions: [
                .init("Save All") {},
                .init("Discard", role: .destructive) {},
                .init("Cancel", role: .cancel) {},
            ]
        )
    }
}
