import Foundation

/// A single snapshot of system metrics, produced by `SystemStore` each tick.
public struct MetricSample: Sendable {
    /// CPU utilization in 0...1.
    public let cpuPercent: Double
    /// The processes using the most CPU (percent), refreshed at 5 seconds.
    public let topCpu: [TopProcess]
    /// The processes using the most resident memory (bytes), 5-second cadence.
    public let topMemory: [TopProcess]
    /// Per-process network rates (bytes/sec), 5-second cadence.
    public let networkProcs: [NetworkProcess]
    /// Names of connected Bluetooth devices, 5-second cadence.
    public let bluetoothDevices: [String]
    /// Fan state (nil before the first heavy sample).
    public let fanStatus: FanStatus?
    /// Memory used bytes out of `memoryTotalBytes`.
    public let memoryUsed: UInt64
    public let memoryTotal: UInt64
    /// CPU temperature in Celsius when the SMC exposes a readable key.
    public let cpuTemperature: Double?
    /// Disk used bytes out of `diskTotal`.
    public let diskUsed: UInt64
    public let diskTotal: UInt64
    /// Network bytes per second, sampled over the last tick.
    public let rxBytesPerSec: UInt64
    public let txBytesPerSec: UInt64
    /// Battery charge 0...1, nil when the machine has no battery.
    public let batteryPercent: Double?
    /// True while a battery is present and being charged.
    public let batteryIsCharging: Bool
    /// Minutes until fully charged (nil when not charging or unavailable).
    public let batteryMinutesToFull: Int?
    /// Full-charge capacity over design capacity, 0...1 (nil when the
    /// hardware or OS does not expose both capacities).
    public let batteryHealthPercent: Double?
    /// Battery charge cycles (nil when unavailable).
    public let batteryCycleCount: Int?
    /// macOS battery condition: "Good", "Fair" or "Poor" (nil when unknown).
    public let batteryCondition: String?
    /// Process thermal state when temperature could not be read.
    public let thermalState: ProcessInfo.ThermalState
    /// Active link (SSID/band or wired); `.offline` when unreadable.
    public let connection: ConnectionInfo
    /// Public (egress) IP and its country, refreshed every 15 minutes.
    public let publicIP: PublicIPInfo
    /// "14:30"-style current time (ticks every second).
    public let timeText: String
    /// "Aug 8" style current date.
    public let dateText: String
    /// "Wed" style current weekday.
    public let weekdayText: String
    /// Human-readable location (district + city) for the location card.
    public let location: LocationInfo
    /// Current-conditions weather snapshot.
    public let weather: WeatherInfo

    public init(
        cpuPercent: Double,
        topCpu: [TopProcess] = [],
        topMemory: [TopProcess] = [],
        networkProcs: [NetworkProcess] = [],
        bluetoothDevices: [String] = [],
        fanStatus: FanStatus? = nil,
        memoryUsed: UInt64,
        memoryTotal: UInt64,
        cpuTemperature: Double?,
        diskUsed: UInt64,
        diskTotal: UInt64,
        rxBytesPerSec: UInt64,
        txBytesPerSec: UInt64,
        batteryPercent: Double?,
        batteryIsCharging: Bool,
        batteryMinutesToFull: Int? = nil,
        batteryHealthPercent: Double? = nil,
        batteryCycleCount: Int? = nil,
        batteryCondition: String? = nil,
        thermalState: ProcessInfo.ThermalState,
        connection: ConnectionInfo = .offline,
        publicIP: PublicIPInfo = .unavailable,
        timeText: String = "",
        dateText: String = "",
        weekdayText: String = "",
        location: LocationInfo = .unavailable,
        weather: WeatherInfo = .unavailable
    ) {
        self.cpuPercent = cpuPercent
        self.topCpu = topCpu
        self.topMemory = topMemory
        self.networkProcs = networkProcs
        self.bluetoothDevices = bluetoothDevices
        self.fanStatus = fanStatus
        self.memoryUsed = memoryUsed
        self.memoryTotal = memoryTotal
        self.cpuTemperature = cpuTemperature
        self.diskUsed = diskUsed
        self.diskTotal = diskTotal
        self.rxBytesPerSec = rxBytesPerSec
        self.txBytesPerSec = txBytesPerSec
        self.batteryPercent = batteryPercent
        self.batteryIsCharging = batteryIsCharging
        self.batteryMinutesToFull = batteryMinutesToFull
        self.batteryHealthPercent = batteryHealthPercent
        self.batteryCycleCount = batteryCycleCount
        self.batteryCondition = batteryCondition
        self.thermalState = thermalState
        self.connection = connection
        self.publicIP = publicIP
        self.timeText = timeText
        self.dateText = dateText
        self.weekdayText = weekdayText
        self.location = location
        self.weather = weather
    }

    public var memoryPercent: Double {
        memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0
    }

    public var diskPercent: Double {
        diskTotal > 0 ? Double(diskUsed) / Double(diskTotal) : 0
    }
}

/// Human-readable byte sizes ("1.2 MB", "3.4 KB/s").
public enum ByteFormat {
    private static let units = ["B", "KB", "MB", "GB", "TB"]
    private static let shortUnits = ["", "K", "M", "G", "T"]

    /// Formats a byte count with unit, e.g. 1_234_567 -> "1.2 MB".
    public static func bytes(_ count: UInt64) -> String {
        format(count, perSecond: false)
    }

    /// Formats a byte count as a rate with a short unit, dropping the "B/s"
    /// suffix, e.g. 12_345 -> "12.3 K".
    public static func rate(_ count: UInt64) -> String {
        var value = Double(count)
        var unitIndex = 0
        while value >= 1000 && unitIndex < Self.shortUnits.count - 1 {
            value /= 1000
            unitIndex += 1
        }
        let number = String(format: "%.1f", value)
        let suffix = Self.shortUnits[unitIndex]
        return suffix.isEmpty ? number : "\(number) \(suffix)"
    }

    private static func format(_ count: UInt64, perSecond: Bool) -> String {
        var value = Double(count)
        var unitIndex = 0
        while value >= 1000 && unitIndex < units.count - 1 {
            value /= 1000
            unitIndex += 1
        }
        let suffix = perSecond ? "\(units[unitIndex])/s" : units[unitIndex]
        return String(format: "%.1f %@", value, suffix)
    }
}

/// Localized time/date strings for the clock card, cheap enough for 1 Hz.
public enum ClockText {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// "Wed" for the given date (defaults to now), in the given locale
    /// (defaults to English).
    public static func weekday(
        _ date: Date = .now,
        locale: Locale = Locale(identifier: "en_US")
    ) -> String {
        date.formatted(Date.FormatStyle(locale: locale).weekday(.abbreviated))
    }

    /// "Aug 8" style current date, in the given locale (defaults to
    /// English, where it renders "Aug 8").
    public static func date(
        _ date: Date = .now,
        locale: Locale = Locale(identifier: "en_US")
    ) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale).month(.abbreviated).day()
        )
    }

    /// "14:30" for the given date (defaults to now).
    public static func time(_ date: Date = .now) -> String {
        timeFormatter.string(from: date)
    }
}