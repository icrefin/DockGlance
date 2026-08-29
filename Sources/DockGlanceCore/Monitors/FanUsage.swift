import Foundation

/// Fan state: how many fans the SMC exposes and their current speeds.
/// `count == 0` (and empty `rpm`) means the machine is fanless or the SMC
/// hides the keys.
public struct FanStatus: Sendable, Equatable {
    public let count: Int
    /// Current RPM per fan, index-aligned with the fan number.
    public let rpm: [Double]

    public init(count: Int, rpm: [Double]) {
        self.count = count
        self.rpm = rpm
    }
}

/// Reads fan state from the SMC on the heavy cadence.
public final class FanUsage {
    public init() {}

    public func sample() -> FanStatus {
        let count = min(SMC.fanCount(), 4)
        guard count > 0 else { return FanStatus(count: 0, rpm: []) }
        var rpm: [Double] = []
        for index in 0..<count {
            if let value = SMC.fanRPM(index) { rpm.append(value) }
        }
        return FanStatus(count: count, rpm: rpm)
    }
}