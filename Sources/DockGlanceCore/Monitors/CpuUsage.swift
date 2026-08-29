import Foundation

/// Reads CPU utilization by diffing kernel CPU load counters.
///
/// Uses `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` which returns the
/// aggregated user/system/nice/idle ticks across all cores; a delta between
/// two calls yields the utilization of the elapsed window.
public final class CpuUsage {
    public init() {}
    private var lastTicks: (work: UInt64, idle: UInt64)?

    /// Returns CPU utilization in 0...1 since the previous call (0 on first).
    public func sample() -> Double {
        let ticks = readTicks()
        defer { lastTicks = ticks }
        guard let last = lastTicks, last.work + last.idle > 0 else { return 0 }
        let workDelta = ticks.work > last.work ? ticks.work - last.work : 0
        let idleDelta = ticks.idle > last.idle ? ticks.idle - last.idle : 0
        let total = workDelta + idleDelta
        return total > 0 ? Double(workDelta) / Double(total) : 0
    }

    private func readTicks() -> (work: UInt64, idle: UInt64) {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCpuInfo
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return (0, 0) }
        let info = Array(UnsafeBufferPointer(start: cpuInfo, count: Int(numCpuInfo)))
        var work: UInt64 = 0
        var idle: UInt64 = 0
        let statePerCore = Int(CPU_STATE_MAX)
        for core in 0..<Int(numCPUs) {
            let offset = core * statePerCore
            work += UInt64(info[offset + Int(CPU_STATE_USER)])
            work += UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
            work += UInt64(info[offset + Int(CPU_STATE_NICE)])
            idle += UInt64(info[offset + Int(CPU_STATE_IDLE)])
        }
        return (work, idle)
    }
}