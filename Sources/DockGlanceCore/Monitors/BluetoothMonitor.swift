import Foundation

/// Names of the Bluetooth devices currently connected, via
/// `system_profiler`. Device names are not exposed through ioreg on
/// recent Apple Silicon (paired devices are hidden); the profiler's JSON
/// is quick (~0.2s) and needs no privileges, so it can run on the heavy
/// (5s) cadence.
public final class BluetoothMonitor {
    public init() {}

    /// Connected device names, in the profiler's order; empty when none.
    public func sample() -> [String] {
        guard let data = run(),
              let root = try? JSONSerialization.jsonObject(with: data)
                  as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]],
              let section = sections.first,
              let connected = section["device_connected"] as? [[String: Any]]
        else { return [] }
        // Each entry is one device, keyed by its display name.
        return connected.compactMap { $0.keys.first }
    }

    private func run() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }
}