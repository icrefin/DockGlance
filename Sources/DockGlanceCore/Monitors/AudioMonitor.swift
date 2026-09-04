import CoreAudio
import Foundation

/// Information about a default audio device (input or output).
public struct AudioDeviceInfo: Sendable, Equatable {
    /// Human-readable device name, "—" when none is available.
    public let name: String
    /// Connection type ("Built-in", "Bluetooth", "USB", …), "—" when unknown.
    public let transport: String
    /// Nominal sample rate in Hz, nil when unreadable.
    public let sampleRate: Double?

    public static let unavailable = AudioDeviceInfo(
        name: "—", transport: "—", sampleRate: nil
    )
}

/// Reads the default input (microphone) and output (speaker) devices via
/// CoreAudio. Property queries only — no subprocesses, no privileges — so it
/// is cheap enough to run on every tick and switches show up within a second.
public final class AudioMonitor {
    public init() {}

    /// The currently selected default microphone and speaker.
    public func sample() -> (microphone: AudioDeviceInfo, speaker: AudioDeviceInfo) {
        (
            microphone: deviceInfo(property: kAudioHardwarePropertyDefaultInputDevice),
            speaker: deviceInfo(property: kAudioHardwarePropertyDefaultOutputDevice)
        )
    }

    /// Resolves the default device for the given hardware property and reads
    /// its name, transport and nominal sample rate.
    private func deviceInfo(
        property: AudioObjectPropertySelector
    ) -> AudioDeviceInfo {
        var address = AudioObjectPropertyAddress(
            mSelector: property,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != 0, size >= MemoryLayout<AudioDeviceID>.size
        else { return .unavailable }
        return AudioDeviceInfo(
            name: deviceName(deviceID),
            transport: transportName(deviceID),
            sampleRate: nominalSampleRate(deviceID)
        )
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(
                deviceID, &address, 0, nil, &size, pointer
            )
        }
        guard status == noErr, let name, (name as String).isEmpty == false
        else { return "—" }
        return name as String
    }

    private func transportName(_ deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &size, &transport
        )
        guard status == noErr else { return "—" }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "Built-in"
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeHDMI: return "HDMI"
        case kAudioDeviceTransportTypeDisplayPort: return "DisplayPort"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        case kAudioDeviceTransportTypeFireWire: return "FireWire"
        case kAudioDeviceTransportTypePCI: return "PCI"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypeVirtual: return "Virtual"
        case kAudioDeviceTransportTypeAggregate: return "Aggregate"
        default: return transport == 0 ? "—" : "External"
        }
    }

    private func nominalSampleRate(_ deviceID: AudioDeviceID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(
            deviceID, &address, 0, nil, &size, &rate
        )
        guard status == noErr, rate > 0 else { return nil }
        return Double(rate)
    }
}
