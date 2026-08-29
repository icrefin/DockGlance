import Darwin
import Foundation

/// Tracks network throughput by diffing interface byte counters.
public final class NetworkUsage {
    public init() {}
    private var lastCounters: (rx: UInt64, tx: UInt64)?
    private var lastReadAt: Date?

    /// Returns a snapshot of (rxBytesPerSec, txBytesPerSec) over the window
    /// since the previous call; (0, 0) on the first call or parse failure.
    public func sample() -> (rx: UInt64, tx: UInt64) {
        let now = Date()
        let counters = readCounters()
        defer {
            lastCounters = counters
            lastReadAt = now
        }
        guard let last = lastCounters else { return (0, 0) }

        // Normalize by the real elapsed time so a stretched window (heavy
        // 5s block, skipped ticks, wake-from-sleep) is not mistaken
        // for a 2-5x rate spike. Clamp guards against coalesced
        // micro-ticks; an over-30s window is treated as 30s.
        let elapsed = now.timeIntervalSince(lastReadAt!)
        let clamped = min(max(elapsed, 0.05), 30)
        let rx = counters.rx >= last.rx ? counters.rx - last.rx : 0
        let tx = counters.tx >= last.tx ? counters.tx - last.tx : 0
        return (UInt64(Double(rx) / clamped), UInt64(Double(tx) / clamped))
    }

    /// Sums live (non-awdl) network interfaces' byte counters.
    private func readCounters() -> (rx: UInt64, tx: UInt64) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return (0, 0) }
        defer { freeifaddrs(head) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var cursor = head
        while true {
            let entry = cursor.pointee
            if entry.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: entry.ifa_name)
                if isUsableInterface(name), let data = entry.ifa_data {
                    let info = data.assumingMemoryBound(to: if_data.self).pointee
                    rx += UInt64(info.ifi_ibytes)
                    tx += UInt64(info.ifi_obytes)
                }
            }
            guard let next = entry.ifa_next else { break }
            cursor = next
        }
        return (rx, tx)
    }

    /// Counts physical "en*" interfaces; skips loopback, AWDL and
    /// bridge artifacts.
    private func isUsableInterface(_ name: String) -> Bool {
        name.hasPrefix("en")
    }
}