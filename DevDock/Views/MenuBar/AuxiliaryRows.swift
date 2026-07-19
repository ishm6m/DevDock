import SwiftUI

/// A compact icon tile shared by the database / docker / tunnel rows.
private struct IconTile: View {
    let systemImage: String
    let colorHex: String
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(hex: colorHex).gradient)
            .frame(width: 28, height: 28)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
            )
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
            )
            .accessibilityHidden(true)
    }
}

struct DatabaseRowView: View {
    let database: DatabaseService
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            IconTile(systemImage: database.kind.symbol, colorHex: database.kind.accentColorHex)
            VStack(alignment: .leading, spacing: 2) {
                Text(database.displayName).font(.system(size: 12, weight: .medium))
                Text("localhost:\(database.port) · PID \(database.pid)")
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if hovering {
                ActionButton(systemImage: "link", help: "Copy connection string") {
                    viewModel.copyConnectionString(database)
                }
            } else {
                StatusDot(color: .green, pulsing: true)
                Text("Running").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { value in
            withAnimation(reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 0.82)) {
                hovering = value
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(database.displayName) running on port \(database.port)")
    }
}

struct DockerRowView: View {
    let container: DockerContainer
    @ObservedObject var viewModel: MenuBarViewModel
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isBusy: Bool { viewModel.isBusy(container) }

    var body: some View {
        HStack(spacing: 10) {
            IconTile(systemImage: "shippingbox.fill", colorHex: container.isRunning ? "#2496ED" : "#8E8E93")
            VStack(alignment: .leading, spacing: 2) {
                Text(container.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(container.status.isEmpty ? container.image : container.status)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if hovering || isBusy {
                if container.primaryURL != nil {
                    ActionButton(systemImage: "safari", help: "Open") { viewModel.openContainer(container) }
                }
                ActionButton(systemImage: "arrow.clockwise", help: "Restart", isBusy: isBusy) {
                    viewModel.restartContainer(container)
                }
                ActionButton(systemImage: "stop.fill", help: "Stop", tint: .red, isBusy: isBusy) {
                    viewModel.stopContainer(container)
                }
            } else {
                StatusDot(color: container.isRunning ? .green : .secondary, pulsing: container.isRunning)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { value in
            withAnimation(reduceMotion ? .easeInOut(duration: 0.1) : .spring(response: 0.28, dampingFraction: 0.82)) {
                hovering = value
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Docker container \(container.name), \(container.isRunning ? "running" : container.state)")
    }
}

struct TunnelRowView: View {
    let tunnel: Tunnel
    @ObservedObject var viewModel: MenuBarViewModel

    var body: some View {
        HStack(spacing: 10) {
            IconTile(systemImage: tunnel.kind.symbol, colorHex: "#6D28D9")
            VStack(alignment: .leading, spacing: 2) {
                Text(tunnel.kind.displayName).font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if tunnel.publicWebURL != nil {
                ActionButton(systemImage: "arrow.up.forward.app", help: "Open public URL") {
                    viewModel.openTunnel(tunnel)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(tunnel.kind.displayName) tunnel")
    }

    private var subtitle: String {
        if let url = tunnel.publicURL { return url }
        if let forwards = tunnel.forwardsTo { return "→ \(forwards)" }
        return "Detected (PID \(tunnel.pid))"
    }
}
