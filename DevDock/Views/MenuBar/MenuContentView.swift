import SwiftUI

/// The root menu bar panel shown by `MenuBarExtra` in `.window` style.
///
/// The panel floats on the system's vibrant material; content stays lightweight and
/// animates insertions/removals against stable identifiers so refreshes never cause
/// the list to jump or flicker.
struct MenuContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            SearchBar(text: $viewModel.searchText)
                .padding(.top, 8)
            content
            Divider()
            footer
        }
        .frame(width: 384)
        .overlay(alignment: .bottom) { toastOverlay }
        // Destructive confirmations are rendered *inside* the panel, not via
        // `.confirmationDialog`/`.alert`. A system dialog is a separate, focus-stealing
        // window; presenting one from a `MenuBarExtra(.window)` panel makes the panel
        // resign key and close — killing the dialog with it. See `ConfirmationOverlay`.
        .overlay {
            if let request = activeConfirmation {
                ConfirmationOverlay(request: request)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.85),
                   value: confirmationToken)
    }

    /// The confirmation currently being requested, if any. A per-server kill takes
    /// precedence over Kill All (a specific request the user just made).
    private var activeConfirmation: ConfirmationRequest? {
        if let server = viewModel.pendingKill {
            return ConfirmationRequest(
                title: "Kill \(server.title)?",
                message: "It receives SIGTERM, escalating to SIGKILL if it doesn't exit.",
                confirmTitle: "Kill",
                onConfirm: { viewModel.confirmPendingKill() },
                onCancel: { viewModel.pendingKill = nil }
            )
        }
        if viewModel.showKillAllConfirmation {
            let count = viewModel.killableServerCount
            let keptFavorites = viewModel.activeServerCount - count
            var message = "Each server receives SIGTERM, escalating to SIGKILL if it doesn't exit."
            if keptFavorites > 0 {
                message += " Your \(keptFavorites) favorite\(keptFavorites == 1 ? "" : "s") stay running."
            }
            return ConfirmationRequest(
                title: "Kill \(count) server\(count == 1 ? "" : "s")?",
                message: message,
                confirmTitle: "Kill All",
                onConfirm: { viewModel.confirmKillAll() },
                onCancel: { viewModel.showKillAllConfirmation = false }
            )
        }
        return nil
    }

    /// Drives the overlay's presentation animation without animating on unrelated
    /// state (a live metric tick shouldn't re-run the transition).
    private var confirmationToken: String {
        if let server = viewModel.pendingKill { return "kill:\(server.id)" }
        if viewModel.showKillAllConfirmation { return "killall" }
        return "none"
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Image(nsImage: MenuBarLabel.rocketGlyph(active: true))
                .resizable()
                .frame(width: 17, height: 18)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("DevDock").font(.system(size: 13, weight: .bold))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            ActionButton(systemImage: "arrow.clockwise", help: "Refresh now") { viewModel.refreshNow() }
            ActionButton(
                systemImage: "xmark.octagon",
                help: "Kill all servers (favorites are kept)",
                tint: .red,
                isEnabled: viewModel.killableServerCount > 0
            ) {
                viewModel.requestKillAll()
            }
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .help("Preferences")
            .accessibilityLabel("Preferences")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var subtitle: String {
        let count = viewModel.activeServerCount
        let base = count == 0 ? "No servers running" : "\(count) server\(count == 1 ? "" : "s") running"
        let attention = viewModel.attentionCount
        guard attention > 0 else { return base }
        return base + (attention == 1 ? " · 1 needs attention" : " · \(attention) need attention")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasAnything {
            EmptyStateView(isSearching: false)
        } else if isEmptyAfterFilter {
            EmptyStateView(isSearching: true)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !viewModel.conflictPortsSummary.isEmpty { conflictBanner }

                    section(title: "Favorites", systemImage: "star.fill", servers: viewModel.favoriteServers)
                    section(title: "Servers", systemImage: "server.rack", servers: viewModel.otherServers)

                    if !viewModel.databases.isEmpty {
                        SectionHeader(title: "Databases", systemImage: "cylinder.split.1x2", count: viewModel.databases.count)
                        ForEach(viewModel.databases) { DatabaseRowView(database: $0, viewModel: viewModel) }
                    }
                    if !viewModel.containers.isEmpty {
                        SectionHeader(title: "Docker", systemImage: "shippingbox", count: viewModel.containers.count)
                        ForEach(viewModel.containers) { DockerRowView(container: $0, viewModel: viewModel) }
                    }
                    if !viewModel.tunnels.isEmpty {
                        SectionHeader(title: "Tunnels", systemImage: "point.3.connected.trianglepath.dotted", count: viewModel.tunnels.count)
                        ForEach(viewModel.tunnels) { TunnelRowView(tunnel: $0, viewModel: viewModel) }
                    }
                    Color.clear.frame(height: 6)
                }
                .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.85), value: layoutToken)
            }
            .frame(maxHeight: 520)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private func section(title: String, systemImage: String, servers: [DevServer]) -> some View {
        if !servers.isEmpty {
            SectionHeader(title: title, systemImage: systemImage, count: servers.count)
            ForEach(servers) { ServerRowView(server: $0, viewModel: viewModel) }
        }
    }

    private var conflictBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Port conflict on \(viewModel.conflictPortsSummary.map(String.init).joined(separator: ", "))")
                .font(.system(size: 11, weight: .medium))
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.orange.opacity(0.14))
        )
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Feedback toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let feedback = viewModel.feedback {
            FeedbackToast(feedback: feedback)
                .padding(.bottom, 44)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.8),
                           value: viewModel.feedback)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Settings")
            Spacer()
            Button {
                viewModel.quit()
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
            .accessibilityLabel("Quit DevDock")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    /// A stable per-item identity list; list layout animates only when membership or
    /// order changes, not when live metrics tick.
    private var layoutToken: [String] {
        viewModel.favoriteServers.map(\.id)
            + viewModel.otherServers.map(\.id)
            + viewModel.databases.map(\.id)
            + viewModel.containers.map(\.id)
            + viewModel.tunnels.map(\.id)
    }

    private var isEmptyAfterFilter: Bool {
        viewModel.favoriteServers.isEmpty
            && viewModel.otherServers.isEmpty
            && viewModel.databases.isEmpty
            && viewModel.containers.isEmpty
            && viewModel.tunnels.isEmpty
    }
}

// MARK: - Feedback toast view

/// A small floating pill that reports the result of an action (kill, restart, …).
private struct FeedbackToast: View {
    let feedback: MenuBarViewModel.ActionFeedback

    private var tint: Color {
        switch feedback.style {
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: feedback.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
            Text(feedback.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(tint.opacity(0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(feedback.message)
    }
}
