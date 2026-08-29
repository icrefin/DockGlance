import Foundation

/// Reads the boot volume's used/total capacity.
public final class DiskUsage {
    public init() {}
    /// Returns (usedBytes, totalBytes) for the root volume, or (0, 1) on error.
    public func sample() -> (used: UInt64, total: UInt64) {
        let url = URL(fileURLWithPath: "/")
        do {
            let values = try url.resourceValues(
                forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
            )
            let total = UInt64(values.volumeTotalCapacity ?? 0)
            let available = UInt64(values.volumeAvailableCapacity ?? 0)
            return (used: total - available, total: total)
        } catch {
            return (0, 1)
        }
    }
}