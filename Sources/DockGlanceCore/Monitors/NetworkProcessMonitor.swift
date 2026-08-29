import Foundation

/// One process' network throughput, in bytes per second.
public struct NetworkProcess: Sendable, Equatable {
    public let name: String
    public let rxBytesPerSec: Double
    public let txBytesPerSec: Double

    public init(name: String, rxBytesPerSec: Double, txBytesPerSec: Double) {
        self.name = name
        self.rxBytesPerSec = rxBytesPerSec
        self.txBytesPerSec = txBytesPerSec
    }
}

/// Per-process network rates via `nettop`. The tool exposes *cumulative*
/// counters only (no per-second columns), so each call snapshots the
/// counters and diffs them against the previous call, dividing by the
/// real elapsed window — the same pattern as `NetworkUsage`. A single
/// `-L 1` run costs a fast subprocess spawn, safe on the heavy cadence.
public final class NetworkProcessMonitor {
    public init() {}

    private var lastCounters: [String: (rx: Double, tx: Double)] = [:]
    private var lastReadAt: Date?

    /// Processes with non-zero traffic, largest first (by combined
    /// in+out). Empty on failure, on the first call, or when nothing used
    /// the network since the previous call.
    public func sample() -> [NetworkProcess] {
        let now = Date()
        let current = readCounters()
        let prev = lastCounters
        let elapsed = lastReadAt.map { now.timeIntervalSince($0) } ?? 0
        defer {
            lastCounters = current
            lastReadAt = now
        }
        guard elapsed >= 0.05 else { return [] }

        var result: [NetworkProcess] = []
        for (name, counters) in current {
            guard let old = prev[name] else { continue } // new process: no delta yet
            let rx = counters.rx >= old.rx ? (counters.rx - old.rx) / elapsed : 0
            let tx = counters.tx >= old.tx ? (counters.tx - old.tx) / elapsed : 0
            guard rx > 0 || tx > 0 else { continue }
            result.append(NetworkProcess(
                name: name, rxBytesPerSec: rx, txBytesPerSec: tx
            ))
        }
        return result.sorted {
            $0.rxBytesPerSec + $0.txBytesPerSec > $1.rxBytesPerSec + $1.txBytesPerSec
        }
    }

    /// A map of process name → cumulative byte counters, from one
    /// `nettop -P -L 1` snapshot (rows `name.pid,rx,tx`).
    private func readCounters() -> [String: (rx: Double, tx: Double)] {
        guard let lines = runNettop() else { return [:] }
        var counters: [String: (rx: Double, tx: Double)] = [:]
        for line in lines.dropFirst() { // drop the header row
            let fields = line.split(separator: ",").map(String.init)
            guard fields.count >= 3,
                  let base = fields[0].split(separator: ".").first else { continue }
            let name = String(base)
            guard !Self.excluded.contains(name),
                  let rx = Double(fields[1]),
                  let tx = Double(fields[2]) else { continue }
            // The last line for a process wins (nettop may repeat rows).
            counters[name] = (rx, tx)
        }
        return counters
    }

    private static let excluded: Set<String> = ["kernel_task"]

    private func runNettop() -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "1", "-J", "bytes_in,bytes_out"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .map(String.init)
    }
}