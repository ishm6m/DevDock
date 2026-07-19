import SwiftUI

// MARK: - Framework badge

/// A rounded, gradient framework badge with a monogram. A license-safe stand-in for
/// official logos, styled to read as an intentional first-party icon (soft gradient,
/// inner highlight, subtle drop shadow). Real logo assets can be dropped into the
/// asset catalog later without touching call sites.
struct FrameworkBadge: View {
    let framework: Framework
    var size: CGFloat = 32

    var body: some View {
        let color = Color(hex: framework.accentColorHex)
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(color.gradient)
            .overlay(
                // Top inner highlight for a little depth.
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.28), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            )
            .overlay(
                Text(framework.monogram)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
                    .padding(2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.4), radius: 3, y: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Metric label

/// A small icon + text metric used in server rows (PID, CPU, memory, uptime…).
struct MetricLabel: View {
    let systemImage: String
    let text: String
    var tint: Color = .secondary
    var accessibilityLabel: String?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.system(size: 9))
                .imageScale(.small)
            Text(text)
                .font(.system(size: 11, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel ?? text)
    }
}

// MARK: - Buttons

/// A subtle press animation applied to icon buttons for tactile feedback.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A compact, hover-highlighting icon button used for row and header actions.
///
/// Provides hover, pressed, disabled, busy, keyboard-focus, and tooltip states, plus
/// a VoiceOver label derived from its help text.
struct ActionButton: View {
    let systemImage: String
    let help: String
    var tint: Color = .primary
    var isEnabled: Bool = true
    var isBusy: Bool = false
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isFocused) private var isFocused

    private var active: Bool { isEnabled && !isBusy }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .frame(width: 30, height: 26)
            .foregroundStyle(active ? AnyShapeStyle(tint) : AnyShapeStyle(Color.secondary.opacity(0.35)))
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovering && active ? tint.opacity(0.16) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.tint.opacity(isFocused ? 0.9 : 0), lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!active)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Section header

/// An uppercase section header with an optional count pill.
struct SectionHeader: View {
    let title: String
    var systemImage: String?
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
            }
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
            if let count {
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.quaternary))
            }
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Status indicators

/// A colored status dot with an optional soft pulse, used to signal a live process.
/// The pulse honors the system Reduce Motion setting.
struct StatusDot: View {
    var color: Color
    var pulsing: Bool = false
    var size: CGFloat = 7

    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shouldPulse: Bool { pulsing && !reduceMotion }

    var body: some View {
        ZStack {
            if shouldPulse {
                Circle()
                    .fill(color.opacity(0.35))
                    .scaleEffect(animate ? 2.4 : 1)
                    .opacity(animate ? 0 : 0.6)
            }
            Circle().fill(color)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard shouldPulse else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
        .accessibilityHidden(true)
    }
}

/// A subtle pill tag (e.g. "LIVE", "CONFLICT").
struct TagView: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 8, weight: .bold)) }
            Text(text.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.4)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(tint.opacity(0.16)))
        .accessibilityLabel(text)
    }
}
