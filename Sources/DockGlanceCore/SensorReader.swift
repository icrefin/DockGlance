import Foundation

/// A snapshot of the non-UI sensors, produced entirely off the main thread.
public struct SensorSnapshot: Sendable {
    public let cpuPercent: Double
    public let cpuTemperature: Double?
    public let memoryUsed: UInt64
    public let memoryTotal: UInt64
    public let diskUsed: UInt64
    public let diskTotal: UInt64
    public let rxBytesPerSec: UInt64
    public let txBytesPerSec: UInt64
    public let batteryPercent: Double?
    public let batteryIsCharging: Bool
    public let batteryMinutesToFull: Int?
    public let topCpu: [TopProcess]
    public let topMemory: [TopProcess]
    public let networkProcs: [NetworkProcess]
    public let bluetoothDevices: [String]
    public let fanStatus: FanStatus?
}

/// Samples the monitors that issue subprocess calls (`ps`, `nettop`) and
/// IOKit/IOHID reads on the actor's own executor, so they can never block
/// the main thread. Cheap reads (CPU, memory, network) run on every call;
/// the heavy reads (disk, temperature, battery, top processes, per-process
/// network) are throttled to every 5 seconds and cached.
public actor SensorReader {
    private let cpu = CpuUsage()
    private let memory = MemoryUsage()
    private let disk = DiskUsage()
    private let network = NetworkUsage()
    private let temperature = TemperatureUsage()
    private let battery = BatteryUsage()
    private let process = ProcessMonitor()
    private let networkProcess = NetworkProcessMonitor()
    private let bluetooth = BluetoothMonitor()
    private let fan = FanUsage()

    private var lastHeavy = Date.distantPast
    private var diskUsed: UInt64 = 0
    private var diskTotal: UInt64 = 1
    private var temperatureValue: Double?
    private var batteryStatus = BatteryStatus.unavailable
    private var topCpu: [TopProcess] = []
    private var topMemory: [TopProcess] = []
    private var networkProcs: [NetworkProcess] = []
    private var bluetoothDevices: [String] = []
    private var fanStatus: FanStatus?

    public init() {}

    public func sample() -> SensorSnapshot {
        let mem = memory.sample()
        let net = network.sample()
        if Date().timeIntervalSince(lastHeavy) >= 5 {
            lastHeavy = Date()
            let diskSample = disk.sample()
            diskUsed = diskSample.used
            diskTotal = diskSample.total
            temperatureValue = temperature.sample()
            batteryStatus = battery.sample()
            let tops = process.sample()
            topCpu = tops.cpu
            topMemory = tops.memory
            networkProcs = networkProcess.sample()
            bluetoothDevices = bluetooth.sample()
            fanStatus = fan.sample()
        }
        return SensorSnapshot(
            cpuPercent: cpu.sample(),
            cpuTemperature: temperatureValue,
            memoryUsed: mem.used,
            memoryTotal: mem.total,
            diskUsed: diskUsed,
            diskTotal: diskTotal,
            rxBytesPerSec: net.rx,
            txBytesPerSec: net.tx,
            batteryPercent: batteryStatus.percent,
            batteryIsCharging: batteryStatus.isCharging,
            batteryMinutesToFull: batteryStatus.timeToFullMinutes,
            topCpu: topCpu,
            topMemory: topMemory,
            networkProcs: networkProcs,
            bluetoothDevices: bluetoothDevices,
            fanStatus: fanStatus
        )
    }
}