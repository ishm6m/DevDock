import SwiftUI

/// A single development server card: framework badge, identity, live status and
/// metrics, project/git context, and a hover-revealed action toolbar.
///
/// The layout follows a deliberate hierarchy — framework → project → localhost URL →
/// status → CPU / memory / uptime → actions — and stays lightweight: no chrome until
/// you hover, at which point it gently elevates and reveals its controls.
struct ServerRowView: View {
    let server: DevServer
    @ObservedObject var viewModel: MenuBarViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hovering = false

    private var isCopied: Bool { viewModel.recentlyCopiedID == server.id }
    private var isBusy: Bool { viewModel.isBusy(server) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            metricsRow
            if hovering || isBusy {
                actionBar
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    server.hasPortConflict ? Color.orange.opacity(0.55) : Color.clear,
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(hovering ? 0.12 : 0), radius: 5, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .onHover { isHovering in
            let animation: Animation = reduceMotion ? .easeInOut(duration: 0.12)
                                                     : .spring(response: 0.3, dampingFraction: 0.8)
            withAnimation(animation) { hovering = isHovering }
        }
    }

    // MARK: - Header (framework · project · url · status)

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            FrameworkBadge(framework: server.framework)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(server.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if server.isManaged {
                        TagView(text: "Live", systemImage: "dot.radiowaves.left.and.right", tint: .green)
                    }
                    if server.hasPortConflict {
                        TagView(text: "Conflict", systemImage: "exclamationmark.triangle.fill", tint: .orange)
                    }
                    // High CPU takes priority so "Idle" only shows for genuinely
                    // low-activity (i.e. likely forgotten) servers.
                    if server.attention.isHighCPU {
                        TagView(text: "High CPU", systemImage: "flame.fill", tint: .orange)
                    } else if server.attention.isForgotten {
                        TagView(text: "Idle", systemImage: "moon.zzz.fill", tint: .yellow)
                    }
                }

                HStack(spacing: 5) {
                    Text(server.framework.displayName)
                    Text("·")
                    Button {
                        viewModel.open(server)
                    } label: {
                        Text(server.port.displayString)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .help("Open \(server.localURL.absoluteString)")
                    .accessibilityLabel("Open \(server.port.displayString) in browser")

                    StatusDot(color: .green, pulsing: true, size: 6)
                        .padding(.leading, 1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                if let project = server.project {
                    projectRow(project)
                }
            }

            Spacer(minLength: 4)

            favoriteButton
        }
    }

    private var favoriteButton: some View {
        Button {
            viewModel.toggleFavorite(server)
        } label: {
            Image(systemName: viewModel.isFavorite(server) ? "star.fill" : "star")
                .font(.system(size: 12))
                .foregroundStyle(viewModel.isFavorite(server) ? .yellow : .secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .help(viewModel.isFavorite(server) ? "Unpin" : "Pin to top")
        .accessibilityLabel(viewModel.isFavorite(server) ? "Unpin \(server.title)" : "Pin \(server.title) to top")
    }

    private func projectRow(_ project: ProjectInfo) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "folder").font(.system(size: 9))
            Text(project.abbreviatedPath)
                .lineLimit(1)
                .truncationMode(.middle)
            if let branch = server.git?.branch, !branch.isEmpty {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                Text(branch).lineLimit(1)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Metrics (cpu · memory · uptime)

    private var metricsRow: some View {
        HStack(spacing: 12) {
            MetricLabel(
                systemImage: "cpu",
                text: server.resources.cpuDisplay,
                tint: server.resources.cpuPercent > 80 ? .orange : .secondary,
                accessibilityLabel: "CPU \(server.resources.cpuDisplay)"
            )
            MetricLabel(
                systemImage: "memorychip",
                text: server.resources.memoryDisplay,
                accessibilityLabel: "Memory \(server.resources.memoryDisplay)"
            )
            MetricLabel(
                systemImage: "clock",
                text: server.runningDuration,
                tint: server.attention.isForgotten ? .yellow : .secondary,
                accessibilityLabel: "Uptime \(server.runningDuration)"
            )
            MetricLabel(
                systemImage: "number",
                text: "\(server.pid)",
                accessibilityLabel: "Process ID \(server.pid)"
            )
            Spacer()
        }
    }

    // MARK: - Actions

    private var actionBar: some View {
        HStack(spacing: 2) {
            ActionButton(systemImage: "safari", help: "Open in browser") { viewModel.open(server) }
            ActionButton(systemImage: "folder", help: "Reveal in Finder") { viewModel.reveal(server) }
            ActionButton(
                systemImage: isCopied ? "checkmark" : "doc.on.doc",
                help: "Copy URL",
                tint: isCopied ? .green : .primary
            ) { viewModel.copyURL(server) }
            ActionButton(
                systemImage: "text.alignleft",
                help: server.isManaged ? "View live logs" : "Logs available after restarting via DevDock",
                isEnabled: server.isManaged
            ) {
                if let pid = server.managedRootPID { openWindow(id: "logs", value: pid) }
            }
            ActionButton(
                systemImage: "arrow.clockwise",
                help: server.canRestart ? "Restart" : "Restart unavailable (unknown command)",
                isEnabled: server.canRestart,
                isBusy: isBusy
            ) { viewModel.restart(server) }
            Spacer()
            ActionButton(
                systemImage: "stop.fill",
                help: "Kill",
                tint: .red,
                isBusy: isBusy
            ) { viewModel.requestKill(server) }
        }
        .padding(.top, 1)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(hovering ? AnyShapeStyle(.quaternary.opacity(0.7)) : AnyShapeStyle(.quaternary.opacity(0.28)))
    }
}
