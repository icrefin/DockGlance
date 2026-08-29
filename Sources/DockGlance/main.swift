import AppKit
import DockGlanceCore
import ServiceManagement

if CommandLine.arguments.contains("--probe") {
    Task { @MainActor in
        probe()
        exit(0)
    }
    dispatchMain()
}

// "--login on|off|status" manages the Start-at-Login registration from the
// command line (e.g. UI automation); the menu uses the same SMAppService.
if let index = CommandLine.arguments.firstIndex(of: "--login"),
   index + 1 < CommandLine.arguments.count {
    let command = CommandLine.arguments[index + 1]
    let service = SMAppService.mainApp
    do {
        switch command {
        case "on":
            if service.status != .enabled { try service.register() }
        case "off":
            if service.status == .enabled { try service.unregister() }
        case "status":
            break
        default:
            print("usage: --login on|off|status")
            exit(2)
        }
        print("login: \(service.status.description)")
        exit(0)
    } catch {
        print("login failed: \(error)")
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

extension SMAppService.Status {
    var description: String {
        switch self {
        case .notRegistered: "notRegistered"
        case .enabled: "enabled"
        case .requiresApproval: "requiresApproval"
        case .notFound: "notFound"
        default: "unknown(\(rawValue))"
        }
    }
}

/// Prints a one-shot sample of every metric (diagnostic / calibration use).
@MainActor
private func probe() {
    let cpu = CpuUsage()
    _ = cpu.sample()
    Thread.sleep(forTimeInterval: 1)
    print("CPU: \(Int((cpu.sample() * 100).rounded()))%")
    let memory = MemoryUsage().sample()
    print("MEM: \(ByteFormat.bytes(memory.used)) / \(ByteFormat.bytes(memory.total))")
    let disk = DiskUsage().sample()
    print("DISK: \(ByteFormat.bytes(disk.used)) / \(ByteFormat.bytes(disk.total))")
    let net = NetworkUsage()
    _ = net.sample()
    Thread.sleep(forTimeInterval: 1)
    let net2 = net.sample()
    print("NET: ↓\(ByteFormat.rate(net2.rx)) ↑\(ByteFormat.rate(net2.tx))")
    for key in ["Tp09", "Tp05", "Tp0T", "T0s", "T0c", "TC0P", "TC0F"] {
        let value = SMC.temperature(forKey: key).map { String(format: "%.1f°C", $0) }
            ?? "nil"
        print("SMC \(key): \(value)  [\(SMC.debugInfo(forKey: key))]")
    }
    let temp = TemperatureUsage().sample()
        .map { String(format: "%.1f°C", $0) } ?? "nil"
    print("TEMP: \(temp)")
    let battery = BatteryUsage().sample()
    let batteryText = battery.percent.map { String(format: "%.0f%%", $0 * 100) }
        ?? "n/a"
    print("BATT: \(batteryText) charging=\(battery.isCharging) plugged=\(battery.isPluggedIn)")
    let connection = ConnectionMonitor().sample()
    print("CONN: \(connection.summary) [\(connection.detail)]")
    print("CLOCK: \(ClockText.time()) \(ClockText.date())")
    let weather = WeatherMonitor()
    weather.refreshIfNeeded()
    Thread.sleep(forTimeInterval: 3)
    let weatherText = weather.info.temperature
        .map { String(format: "%.0f°C", $0) } ?? "n/a"
    print("WEATHER: \(weather.info.title) \(weatherText)")
}