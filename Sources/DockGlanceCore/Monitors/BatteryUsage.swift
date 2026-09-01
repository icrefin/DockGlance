import Foundation
import IOKit
import IOKit.ps

/// Battery status exposed to the UI.
public struct BatteryStatus: Sendable {
    public let percent: Double?
    public let isCharging: Bool
    public let isPluggedIn: Bool
    /// Minutes remaining until fully charged (nil when not available).
    public let timeToFullMinutes: Int?
    /// Full-charge capacity over design capacity, 0...1 (nil when the
    /// hardware or OS does not expose both capacities).
    public let healthPercent: Double?
    /// Charge cycles accumulated by the battery (nil when unavailable).
    public let cycleCount: Int?
    /// macOS battery condition: "Good", "Fair" or "Poor" (nil when unknown).
    public let condition: String?

    public init(
        percent: Double?, isCharging: Bool, isPluggedIn: Bool,
        timeToFullMinutes: Int? = nil, healthPercent: Double? = nil,
        cycleCount: Int? = nil, condition: String? = nil
    ) {
        self.percent = percent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.timeToFullMinutes = timeToFullMinutes
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
        self.condition = condition
    }

    public static let unavailable = BatteryStatus(
        percent: nil, isCharging: false, isPluggedIn: false
    )
}

/// Reads the battery state from the power sources registry.
public final class BatteryUsage {
    public init() {}

    /// Returns charge percent, charging flag and power source state.
    public func sample() -> BatteryStatus {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue()
              as? [CFTypeRef]
        else {
            return .unavailable
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any]
            else { continue }
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 0
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            guard max > 0 else { continue }
            let percent = Double(current) / Double(max)
            let isCharging =
                (description[kIOPSIsChargingKey] as? Bool) ?? false
            let state = description[kIOPSPowerSourceStateKey] as? String
            let plugged = state == kIOPSACPowerValue
            // The OS reports sentinel values (-1, 0 or Int32.max) instead of
            // an estimate when it cannot compute the time — treat those as
            // "unknown" so the UI never shows a nonsense duration.
            let rawMinutes = description[kIOPSTimeToFullChargeKey] as? Int
            let plausibleMinutes = (rawMinutes ?? 0) > 0 && (rawMinutes ?? 0) < 24 * 60
                ? rawMinutes
                : nil
            return BatteryStatus(
                percent: percent,
                isCharging: isCharging,
                isPluggedIn: plugged,
                timeToFullMinutes: isCharging ? plausibleMinutes : nil,
                healthPercent: health.healthPercent,
                cycleCount: health.cycleCount,
                condition: health.condition
            )
        }
        return .unavailable
    }

    /// Reads battery health from the `AppleSmartBattery` IORegistry entry
    /// (`IOPMCopyBatteryHealthInfo` is no longer exported on modern macOS):
    /// health percentage = raw full-charge capacity over design capacity
    /// (capped at 100%, matching what macOS shows), cycle count, and a
    /// Good/Fair/Poor condition derived with the usual 80% service
    /// threshold. Returns nils on desktops or when values are missing.
    private var health: (
        healthPercent: Double?, cycleCount: Int?, condition: String?
    ) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"),
            &iterator
        ) == KERN_SUCCESS else { return (nil, nil, nil) }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return (nil, nil, nil) }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            service, &unmanaged, kCFAllocatorDefault, 0
        ) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return (nil, nil, nil) }

        let design = props["DesignCapacity"] as? Int ?? 0
        let maxCapacity = props["AppleRawMaxCapacity"] as? Int
            ?? props["NominalChargeCapacity"] as? Int ?? 0
        guard design > 0, maxCapacity > 0 else {
            return (nil, props["CycleCount"] as? Int, nil)
        }
        let healthPercent = min(Double(maxCapacity) / Double(design), 1.0)
        let condition = condition(for: healthPercent)
        return (healthPercent, props["CycleCount"] as? Int, condition)
    }

    /// Good/Fair/Poor from the health percentage; 80% is where macOS
    /// starts recommending battery service.
    private func condition(for healthPercent: Double) -> String {
        healthPercent >= 0.8
            ? kIOPSGoodValue
            : (healthPercent >= 0.5 ? kIOPSFairValue : kIOPSPoorValue)
    }
}