import Foundation

/// A snapshot of a process's resource consumption.
struct ResourceUsage: Hashable, Codable {
    var cpuPercent: Double
    var memoryBytes: UInt64

    var memoryDisplay: String { Formatters.memory(bytes: memoryBytes) }
    var cpuDisplay: String { Formatters.cpu(percent: cpuPercent) }
}
