import Foundation
import UserNotifications

/// Wraps `UNUserNotificationCenter` for DevDock's lifecycle alerts.
///
/// Notifications are delivered via the local notification center, so they respect
/// the user's system notification settings and Focus modes automatically.
final class NotificationManager: @unchecked Sendable {

    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Log.app.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
            } else {
                Log.app.info("Notification authorization granted: \(granted, privacy: .public)")
            }
        }
    }

    func serverStarted(_ server: DevServer) {
        post(
            title: "Server Started",
            body: "\(server.title) — \(server.framework.displayName) on localhost:\(server.port.number)"
        )
    }

    func serverStopped(title: String, port: Int) {
        post(title: "Server Stopped", body: "\(title) on localhost:\(port) is no longer running")
    }

    func portConflict(port: Int) {
        post(title: "Port Conflict", body: "Multiple processes are competing for port \(port)")
    }

    func serverNeedsAttention(_ server: DevServer) {
        let reason: String
        switch (server.attention.isForgotten, server.attention.isHighCPU) {
        case (true, true):  reason = "has been running a while and is using high CPU"
        case (_, true):     reason = "is using high CPU"
        default:            reason = "has been running for a while"
        }
        post(
            title: "Server Still Running",
            body: "\(server.title) on localhost:\(server.port.number) \(reason). Still need it?"
        )
    }

    func serverWillAutoStop(_ server: DevServer, idleHours: Int, inMinutes: Int) {
        post(
            title: "Server Still Idle",
            body: "\(server.title) on localhost:\(server.port.number) has been idle for \(idleHours)h — DevDock will stop it in about \(inMinutes) min. Open DevDock to keep it."
        )
    }

    func serverAutoStopped(title: String, port: Int, idleHours: Int) {
        post(
            title: "Auto-Stopped Idle Server",
            body: "\(title) on localhost:\(port) was idle for \(idleHours)h and has been stopped."
        )
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                Log.app.error("Failed to post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
