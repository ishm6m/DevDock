import Foundation

/// Small, dependency-free formatting helpers used across the UI.
///
/// These are pure functions so they can be unit-tested deterministically.
enum Formatters {

    /// Formats a byte count as a compact memory string, e.g. `310 MB`, `1.2 GB`.
    static func memory(bytes: UInt64) -> String {
        guard bytes > 0 else { return "—" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        // Whole numbers below GB read cleaner without decimals.
        if index >= 3 {
            return String(format: "%.1f %@", value, units[index])
        }
        return String(format: "%.0f %@", value.rounded(), units[index])
    }

    /// Formats a CPU percentage, e.g. `18%`, `0%`, `104%` (multi-core is possible).
    static func cpu(percent: Double) -> String {
        String(format: "%.0f%%", max(0, percent))
    }

    /// Formats an elapsed duration compactly, e.g. `1h 42m`, `3m 12s`, `8s`.
    static func duration(since start: Date, now: Date = Date()) -> String {
        duration(seconds: max(0, now.timeIntervalSince(start)))
    }

    static func duration(seconds total: TimeInterval) -> String {
        let seconds = Int(total)
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let secs = seconds % 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(secs)s" }
        return "\(secs)s"
    }

    /// Abbreviates an absolute path with `~` for the home directory.
    static func abbreviatePath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
