import Foundation

/// Fan state: how many fans the SMC exposes and their current speeds.
/// `count == 0` (and empty `rpm`) means the machine really is fanless.
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
    /// More fans than this are not worth a line in the pop-up.
    private static let maxFans = 4
    /// Readings outside this range are a failed read, not a fan speed.
    private static let plausibleRPM: ClosedRange<Double> = 0...20_000

    public init() {}

    /// `nil` when the SMC cannot be read at all, i.e. the fan count is
    /// unknown. A status with `count == 0` means the machine really is
    /// fanless — conflating the two is what used to label every Mac whose
    /// SMC could not be read (every Apple-Silicon one) as fanless. With
    /// `count > 0` but an empty `rpm` the fans exist yet no speed was
    /// readable this round.
    public func sample() -> FanStatus? {
        guard let reported = Self.fanCount() else { return nil }
        let count = min(max(reported, 0), Self.maxFans)
        guard count > 0 else { return FanStatus(count: 0, rpm: []) }
        let rpm = (0..<count).compactMap { index -> Double? in
            guard let value = SMC.fanRPM(index),
                  Self.plausibleRPM.contains(value)
            else { return nil }
            return value
        }
        return FanStatus(count: count, rpm: rpm)
    }

    /// Fan count from the firmware, or nil when it cannot be established.
    ///
    /// FNum is the direct answer. When it is missing, a fan that still
    /// reports a speed proves at least one fan; a responsive SMC (`#KEY`
    /// readable) that exposes no fan key at all means a genuinely fanless
    /// Mac, while an unresponsive SMC means we simply do not know — and
    /// "unknown" must stay distinct from "fanless".
    private static func fanCount() -> Int? {
        if let reported = SMC.fanCount() { return reported }
        let responsive = SMC.keyCount() != nil
        let fansWithSpeed = (0..<maxFans).filter { SMC.fanRPM($0) != nil }.count
        return resolveFanCount(
            reported: nil,
            responsive: responsive,
            fansWithSpeed: fansWithSpeed
        )
    }

    /// The counting rule, separated from the SMC I/O so it is testable
    /// without the hardware.
    public static func resolveFanCount(
        reported: Int?, responsive: Bool, fansWithSpeed: Int
    ) -> Int? {
        if let reported { return reported }
        if fansWithSpeed > 0 { return fansWithSpeed }
        return responsive ? 0 : nil
    }
}
