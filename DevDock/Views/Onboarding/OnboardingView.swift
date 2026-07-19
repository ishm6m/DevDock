import SwiftUI
import AppKit

/// The one-time first-run welcome.
///
/// Solves three things a menu-bar-only (`LSUIElement`) app gets wrong by default:
/// it proves DevDock actually launched (there's no dock icon or window otherwise) and
/// points the user at the menu-bar item; it states the safety model up front (DevDock
/// is non-sandboxed and can stop processes); and it *primes* notification permission
/// with the value proposition before the system prompt fires, instead of a cold ask at
/// launch that gets denied. Presentation and lifecycle live in `OnboardingController`.
struct OnboardingView: View {
    /// Called when the user opts into notifications. The window still finishes after.
    let onEnableNotifications: () -> Void
    /// Called to complete onboarding and dismiss, whichever button was used.
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 28)
            features
            Divider().padding(.horizontal, 28)
            footer
        }
        .frame(width: 460)
        .background(.regularMaterial)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            appTile
            Text("Welcome to DevDock")
                .font(.system(size: 22, weight: .bold))
            Text("Your local dev servers, one glance away.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            menuBarCallout
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .padding(.horizontal, 28)
    }

    /// The app's own icon, matching the About tab for a consistent identity.
    private var appTile: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
    }

    /// Points the user at the menu-bar item — the "where did it go?" fix.
    private var menuBarCallout: some View {
        HStack(spacing: 9) {
            Image(systemName: "menubar.arrow.up.rectangle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("DevDock lives in your menu bar. Click the bolt up top anytime to see what's running.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        )
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Features

    private var features: some View {
        VStack(alignment: .leading, spacing: 16) {
            FeatureRow(
                systemImage: "bolt.horizontal.fill",
                tint: .accentColor,
                title: "See everything",
                detail: "Every dev server, database, Docker container, and tunnel — with live CPU, memory, and uptime."
            )
            FeatureRow(
                systemImage: "cursorarrow.click.2",
                tint: .blue,
                title: "One-click control",
                detail: "Open, copy a URL, restart, or stop a server without touching Terminal."
            )
            FeatureRow(
                systemImage: "lock.shield.fill",
                tint: .green,
                title: "Private & safe",
                detail: "DevDock only ever acts on processes you own, never signals itself, and is open source under the MIT License."
            )
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    // MARK: - Footer (notification priming + finish)

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Get a nudge when a server has been running a while or is burning CPU, so you can reclaim ports and battery.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            HStack {
                Button("Not Now") { onFinish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onEnableNotifications()
                    onFinish()
                } label: {
                    Text("Enable Notifications")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 22)
    }
}

/// A single icon + title + description line in the welcome's feature list.
private struct FeatureRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
