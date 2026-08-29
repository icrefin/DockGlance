import Foundation
import DockGlanceCore
import Observation

/// Owns the metrics and publishes a fresh `MetricSample` every tick. All
/// blocking sampling (subprocesses, IOKit/IOHID) runs on `SensorReader`'s
/// executor, never the main thread; the main run loop only retrieves recent
/// results and combines them with the UI-bound monitors (connection,
/// weather, public IP).
@MainActor
@Observable
final class SystemStore {
    var sample = MetricSample(
        cpuPercent: 0,
        memoryUsed: 0,
        memoryTotal: 1,
        cpuTemperature: nil,
        diskUsed: 0,
        diskTotal: 1,
        rxBytesPerSec: 0,
        txBytesPerSec: 0,
        batteryPercent: nil,
        batteryIsCharging: false,
        thermalState: .nominal
    )

    private let sensorReader = SensorReader()
    private let connection = ConnectionMonitor()
    private let weather = WeatherMonitor()
    private let publicIpMonitor = PublicIpMonitor()

    /// Locale for the date/weekday cards; updated when the UI language
    /// changes (English by default).
    var clockLocale = Locale(identifier: "en_US")

    /// CPU temperature history for the trend sparkline (1 Hz, ~2 minutes).
    private(set) var temperatureHistory: [Double] = []

    private var sampleTimer: Timer?
    private var isPolling = false
    private var latest: SensorSnapshot?

    /// Starts the 1-second sampling loop on the main run loop (in the
    /// common modes, so it also fires while modals/menus are up). A run-loop
    /// timer is used rather than a Swift `Task.sleep` loop, whose dispatch
    /// backed sleep can fail to resume after a long system sleep in a
    /// background agent — leaving the clock frozen. Each fire only kicks an
    /// async poll; the blocking sensor work happens off the main thread.
    func start() {
        guard sampleTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        sampleTimer = timer
        poll()
    }

    func stop() {
        sampleTimer?.invalidate()
        sampleTimer = nil
    }

    /// Issues one snapshot request; guards against overlapping in-flight
    /// polls so a slow background sample can never queue up on the main
    /// thread.
    private func poll() {
        guard !isPolling else { return }
        isPolling = true
        Task {
            defer { self.isPolling = false }
            self.latest = await self.sensorReader.sample()
            self.publish()
        }
    }

    private func publish() {
        guard let s = latest else { return }
        if let temperature = s.cpuTemperature {
            temperatureHistory.append(temperature)
            if temperatureHistory.count > 120 {
                temperatureHistory.removeFirst(temperatureHistory.count - 120)
            }
        }
        weather.refreshIfNeeded()
        publicIpMonitor.refreshIfNeeded()
        sample = MetricSample(
            cpuPercent: s.cpuPercent,
            topCpu: s.topCpu,
            topMemory: s.topMemory,
            networkProcs: s.networkProcs,
            bluetoothDevices: s.bluetoothDevices,
            fanStatus: s.fanStatus,
            memoryUsed: s.memoryUsed,
            memoryTotal: s.memoryTotal,
            cpuTemperature: s.cpuTemperature,
            diskUsed: s.diskUsed,
            diskTotal: s.diskTotal,
            rxBytesPerSec: s.rxBytesPerSec,
            txBytesPerSec: s.txBytesPerSec,
            batteryPercent: s.batteryPercent,
            batteryIsCharging: s.batteryIsCharging,
            batteryMinutesToFull: s.batteryMinutesToFull,
            thermalState: ProcessInfo.processInfo.thermalState,
            connection: connection.sample(),
            publicIP: publicIpMonitor.info,
            timeText: ClockText.time(),
            dateText: ClockText.date(locale: clockLocale),
            weekdayText: ClockText.weekday(locale: clockLocale),
            location: weather.location,
            weather: weather.info
        )
    }
}