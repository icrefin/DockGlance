import Foundation

/// Reads physical memory usage from the mach VM statistics.
public final class MemoryUsage {
    public init() {}
    private var pageSize: UInt64 = 0

    /// Returns (used, total) bytes. Used counts active + inactive + wired +
    /// compressed pages (the standard "pressure-relevant" definition).
    public func sample() -> (used: UInt64, total: UInt64) {
        if pageSize == 0 {
            var size: vm_size_t = 0
            host_page_size(mach_host_self(), &size)
            pageSize = UInt64(size)
        }
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 1) }

        let free = UInt64(stats.free_count)
        let used = UInt64(stats.active_count)
            + UInt64(stats.inactive_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        let totalPages = free + used
        return (used * pageSize, max(totalPages, 1) * pageSize)
    }
}