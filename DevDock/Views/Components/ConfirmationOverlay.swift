import SwiftUI

/// An in-panel confirmation prompt for destructive actions.
///
/// Why not `.confirmationDialog`/`.alert`? A `MenuBarExtra(.window)` panel is a
/// transient, non-activating `NSPanel` that dismisses the instant it loses key focus.
/// A system dialog presents as a *separate*, focus-stealing window, so presenting one
/// from inside the panel makes the panel resign key and close — taking the dialog
/// (hosted in the panel's view tree) down with it. The buttons never wire up and the
/// whole popover vanishes. Rendering the confirmation *inside* the panel's own view
/// hierarchy keeps focus in one window, so the panel stays open and the buttons work.
struct ConfirmationOverlay: View {
    let request: ConfirmationRequest
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Scrim: dims the panel and swallows taps on the content behind it.
            // Tapping the scrim cancels, matching a dialog's click-outside behavior.
            Rectangle()
                .fill(.black.opacity(0.28))
                .contentShape(Rectangle())
                .onTapGesture { request.onCancel() }

            card
                .padding(.horizontal, 24)
        }
        .transition(
            reduceMotion
                ? .opacity
                : .opacity.combined(with: .scale(scale: 0.96))
        )
    }

    private var card: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text(request.title)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = request.message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button(role: .cancel) { request.onCancel() } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(ConfirmationButtonStyle(kind: .neutral))
                .keyboardShortcut(.cancelAction)

                Button(role: .destructive) { request.onConfirm() } label: {
                    Text(request.confirmTitle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(ConfirmationButtonStyle(kind: .destructive))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(maxWidth: 300)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
        )
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// A pill button used inside `ConfirmationOverlay`; a filled red for the destructive
/// action, a subtle bordered fill for cancel.
private struct ConfirmationButtonStyle: ButtonStyle {
    enum Kind { case neutral, destructive }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(kind == .destructive ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.primary.opacity(kind == .neutral ? 0.12 : 0), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func fill(pressed: Bool) -> AnyShapeStyle {
        switch kind {
        case .destructive:
            return AnyShapeStyle(Color.red.opacity(pressed ? 0.8 : 1))
        case .neutral:
            return AnyShapeStyle(Color.primary.opacity(pressed ? 0.12 : 0.06))
        }
    }
}

/// A described destructive confirmation, presented by `ConfirmationOverlay`.
struct ConfirmationRequest {
    let title: String
    var message: String?
    let confirmTitle: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
}
