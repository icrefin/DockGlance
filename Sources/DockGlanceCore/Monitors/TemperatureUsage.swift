import CoreFoundation
import Foundation
import IOKit

/// Reads CPU temperature, preferring the SMC and falling back to the
/// IOHID event system (the same trick macmon uses) when the SMC does not
/// expose readable keys — which is every Apple-Silicon Mac we probed.
///
/// The IOHID path requires no privileges: Apple's thermal framework
/// publishes temperature services matched by usage page `0xff00` and
/// usage `0x0005`; each service's "Product" name identifies the sensor
/// (e.g. "PMU tdieN" on M-series, "pACC MTR Temp Sensor" elsewhere).
/// We average all sensors whose name advertises a die/Core temperature.
///
/// Read off the main thread (from `SensorReader`); the IOHID one-shot
/// queries are safe on a background thread.
public final class TemperatureUsage {
    private var activeKey: String?
    private let hid = HIDTemperatureReader()

    private static let intelKeys = ["TC0P", "TC0F", "TC0H", "Tp01", "Tp05"]
    private static let appleSiliconKeys = ["Tp09", "Tp05", "Tp0T", "T0s", "T0c"]

    public init() {}

    /// Returns CPU temperature in Celsius, or nil when unavailable.
    public func sample() -> Double? {
        guard let smc = smcSample() else {
            return hid.dieTemperature()
        }
        return smc
    }

    private func smcSample() -> Double? {
        if let activeKey {
            return plausible(SMC.temperature(forKey: activeKey))
        }
        let candidates: [String] = isAppleSilicon ? Self.appleSiliconKeys
            : Self.intelKeys
        for key in candidates {
            if let value = plausible(SMC.temperature(forKey: key)) {
                activeKey = key
                return value
            }
        }
        return nil
    }

    private func plausible(_ value: Double?) -> Double? {
        guard let value, value >= 0, value < 130 else { return nil }
        return value
    }

    private var isAppleSilicon: Bool {
        #if arch(arm64)
            return true
        #else
            return false
        #endif
    }
}

/// Reads temperature sensors published by the IOHID event system.
private final class HIDTemperatureReader {
    private lazy var system: OpaquePointer? =
        IOHIDEventSystemClientCreate(kCFAllocatorDefault)

    /// Averages plausible readings from die/core temperature sensors,
    /// or nil when the system exposes none.
    func dieTemperature() -> Double? {
        let readings = readSensors().filter {
            $0.name.contains("tdie")
                || $0.name.contains("MTR")
                || $0.name.contains("pACC")
        }
        let values = readings.map(\.value).filter { $0 > 0 && $0 < 130 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Returns every matched sensor's (name, celsius) pair.
    private func readSensors() -> [(name: String, value: Double)] {
        guard let system else { return [] }
        IOHIDEventSystemClientSetMatching(system, matchingDictionary)
        guard let services = IOHIDEventSystemClientCopyServices(system)?
            .takeRetainedValue()
        else { return [] }

        var result: [(name: String, value: Double)] = []
        for index in 0..<CFArrayGetCount(services) {
            guard let raw = CFArrayGetValueAtIndex(services, index) else { continue }
            let service = OpaquePointer(raw)
            guard let name = serviceName(service) else { continue }
            guard let event = IOHIDServiceClientCopyEvent(
                service, kIOHIDEventTypeTemperature, 0, 0
            ) else { continue }
            let value = IOHIDEventGetFloatValue(event, kIOHIDEventTypeTemperature << 16)
            result.append((name, value))
        }
        return result
    }

    private func serviceName(_ service: OpaquePointer?) -> String? {
        guard let product = IOHIDServiceClientCopyProperty(service, "Product" as CFString)?
            .takeRetainedValue()
        else { return nil }
        return product as? String
    }

    private var matchingDictionary: CFDictionary {
        [
            "PrimaryUsagePage": kHIDPage_AppleVendor,
            "PrimaryUsage": kHIDUsage_AppleVendor_TemperatureSensor,
        ] as CFDictionary
    }
}

// MARK: - IOHID bindings

private let kHIDPage_AppleVendor: Int = 0xff00
private let kHIDUsage_AppleVendor_TemperatureSensor: Int = 0x0005
private let kIOHIDEventTypeTemperature: Int64 = 15

@_silgen_name("IOHIDEventSystemClientCreate")
private func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?)
    -> OpaquePointer?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func IOHIDEventSystemClientSetMatching(
    _ client: OpaquePointer?, _ matching: CFDictionary?
) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func IOHIDEventSystemClientCopyServices(_ client: OpaquePointer?)
    -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func IOHIDServiceClientCopyProperty(
    _ service: OpaquePointer?, _ key: CFString?
) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDServiceClientCopyEvent")
private func IOHIDServiceClientCopyEvent(
    _ service: OpaquePointer?, _ type: Int64, _ options: Int32,
    _ timestamp: Int64
) -> OpaquePointer?

@_silgen_name("IOHIDEventGetFloatValue")
private func IOHIDEventGetFloatValue(_ event: OpaquePointer?, _ field: Int64)
    -> Double