import Foundation
import IOKit.ps

/// Battery status exposed to the UI.
public struct BatteryStatus: Sendable {
    public let percent: Double?
    public let isCharging: Bool
    public let isPluggedIn: Bool
    /// Minutes remaining until fully charged (nil when not available).
    public let timeToFullMinutes: Int?

    public init(
        percent: Double?, isCharging: Bool, isPluggedIn: Bool,
        timeToFullMinutes: Int? = nil
    ) {
        self.percent = percent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.timeToFullMinutes = timeToFullMinutes
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
                timeToFullMinutes: isCharging ? plausibleMinutes : nil
            )
        }
        return .unavailable
    }
}