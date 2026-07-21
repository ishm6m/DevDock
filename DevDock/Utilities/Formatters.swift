import Foundation

/// Small, dependency-free formatting helpers used across the UI.
///
/// These are pure functions so they can be unit-tested deterministically.
enum Formatters {

    /// Formats a byte count as a compact memory string, e.g. `310 MB`, `1.4 GB`.
    static func memory(bytes: UInt64) -> String {
        guard bytes > 0 else { return "—" }
        return bytes.formatted(.byteCount(style: .memory))
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
        durationFormatter.string(from: max(0, total)) ?? "0s"
    }

    /// Shared because `DateComponentsFormatter` isn't cheap to build and every call site
    /// is a server row re-rendering on each refresh.
    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute, .second]
        formatter.maximumUnitCount = 2      // "1d 1h", never "1d 1h 0m 0s"
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    /// Abbreviates an absolute path with `~` for the home directory.
    static func abbreviatePath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
