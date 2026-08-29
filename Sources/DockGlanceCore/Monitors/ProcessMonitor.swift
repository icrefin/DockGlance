import Foundation

/// A process "winner": a name plus one intrinsic magnitude — CPU percent
/// for the CPU list, resident bytes for the memory list.
public struct TopProcess: Sendable, Equatable {
    public let name: String
    public let value: Double

    public init(name: String, value: Double) {
        self.name = name
        self.value = value
    }
}

/// Reports the processes using the most CPU and the most memory, parsed
/// from `ps` (already sorted by the requested metric). Cheap enough for
/// the 5-second slow cadence.
public final class ProcessMonitor {
    public init() {}

    /// The `count` processes with the highest CPU usage, and the `count`
    /// with the highest resident memory.
    public func sample(count: Int = 5) -> (cpu: [TopProcess], memory: [TopProcess]) {
        (
            cpu: top(args: ["-A", "-r", "-o", "%cpu=,comm="], count: count),
            memory: top(args: ["-A", "-m", "-o", "rss=,comm="], count: count)
        )
    }

    /// The first `count` meaningful lines from a `ps` run sorted by the
    /// requested metric: lowest-slack, non-self processes with a positive
    /// value.
    private func top(args: [String], count: Int) -> [TopProcess] {
        guard let lines = runPS(args: args) else { return [] }
        var result: [TopProcess] = []
        for raw in lines {
            let parts = raw.trimmingCharacters(in: .whitespaces)
                .split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 2, let value = Double(parts[0]), value > 0 else { continue }
            let name = basename(parts.dropFirst().joined(separator: " "))
            guard !name.isEmpty, !Self.excluded.contains(name) else { continue }
            result.append(TopProcess(name: name, value: value))
            if result.count >= count { break }
        }
        return result
    }

    private static let excluded: Set<String> = ["DockGlance", "metrics", "ps", "nettop"]

    private func basename(_ name: String) -> String {
        name.contains("/") ? String(name.split(separator: "/").last ?? "") : name
    }

    private func runPS(args: [String]) -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        // Bound the wait: a stalled/starved `ps` must never hang us.
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        _ = done.wait(timeout: .now() + 2)
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .map(String.init)
    }
}