import Foundation
import IOKit

/// Minimal userspace bridge to the "AppleSMC" driver via IOKit.
///
/// The key data structure must byte-match the kernel's `SMCKeyData_t`.
/// It is made only of fixed-size stored properties, which follow the same
/// layout rules as C structs.
///
/// Every request goes through selector 2 (`kSMCHandleYPCEvent`); the command
/// travels in the request's `data8` field (`kSMCReadKeyInfo` / `kSMCReadKey`).
/// The numbered selectors some older sample code used (9 for key info, 1 for
/// bytes) are not implemented by the current user client: selector 9 answers
/// `kIOReturnUnsupported`, which used to make every Apple-Silicon read fail
/// and thus report the machine as fanless. Byte reads also need the
/// user-client open command (selector 0) once per connection; without it the
/// firmware answers with SMC result 0x87 ("not readable").
///
/// IOKit reads are safe off the main thread; SMC is called from
/// `SensorReader`'s background executor.
public enum SMC {
    private static let serviceName = "AppleSMC"
    // Accessed only from SensorReader's serial executor.
    private nonisolated(unsafe) static var connection: io_connect_t = 0
    private nonisolated(unsafe) static var isOpen = false

    /// "flt ", "sp78", "ui8 ", "ui16", "ui32" and "fpe2" SMC type tags.
    private static let typeFlt: UInt32 = 0x666C7420
    private static let typeSp78: UInt32 = 0x73703738
    private static let typeUi8: UInt32 = 0x75693820 // "ui8 "
    private static let typeUi16: UInt32 = 0x75693136 // "ui16"
    private static let typeUi32: UInt32 = 0x75693332 // "ui32"
    private static let typeFpe2: UInt32 = 0x66706532 // "fpe2"

    private enum Selector: UInt32 {
        /// Opens the user client; required before any key can be read.
        case openUserClient = 0
        /// Runs a single SMC command, named by the request's `data8`.
        case handleYPCEvent = 2
    }

    /// Commands carried in `SMCKeyData.data8`.
    private enum Command: UInt8 {
        case readBytes = 5
        case readKeyInfo = 9
    }

    private struct KeyInfo {
        var dataSize: UInt32
        var dataType: UInt32
    }

    private struct SMCBytes {
        var b0: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        var b1: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        var b2: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        var b3: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

        /// The kernel struct carries at most 32 payload bytes.
        static var byteCount: Int { MemoryLayout<SMCBytes>.size }

        var count: Int { Self.byteCount }

        func byte(at index: Int) -> UInt8 {
            withUnsafeBytes(of: self) { $0.load(fromByteOffset: index, as: UInt8.self) }
        }
    }

    private struct SMCKeyData {
        var key: UInt32 = 0
        var vers = (
            major: UInt8(0), minor: UInt8(0), build: UInt8(0),
            reserved: UInt8(0), release: UInt16(0)
        )
        var pLimitData = (
            version: UInt16(0), length: UInt16(0),
            cpuPLimit: UInt32(0), gpuPLimit: UInt32(0), memPLimit: UInt32(0)
        )
        var keyInfo = (dataSize: UInt32(0), dataType: UInt32(0), attributes: UInt32(0))
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes = SMCBytes(
            b0: (0, 0, 0, 0, 0, 0, 0, 0),
            b1: (0, 0, 0, 0, 0, 0, 0, 0),
            b2: (0, 0, 0, 0, 0, 0, 0, 0),
            b3: (0, 0, 0, 0, 0, 0, 0, 0)
        )
    }

    private static func ensureOpen() -> Bool {
        if isOpen { return true }
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching(serviceName)
        )
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var newConnection: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &newConnection)
        guard result == kIOReturnSuccess else { return false }
        connection = newConnection
        var request = SMCKeyData()
        _ = callRaw(.openUserClient, &request)
        isOpen = true
        return true
    }

    private static func call(
        _ selector: Selector,
        _ input: inout SMCKeyData
    ) -> SMCKeyData? {
        guard ensureOpen() else { return nil }
        return callRaw(selector, &input)
    }

    private static func callRaw(
        _ selector: Selector,
        _ input: inout SMCKeyData
    ) -> SMCKeyData? {
        var output = SMCKeyData()
        var outSize = MemoryLayout<SMCKeyData>.size
        let ioResult = withUnsafeMutablePointer(to: &input) { inputPtr in
            withUnsafeMutablePointer(to: &output) { outputPtr in
                IOConnectCallStructMethod(
                    connection,
                    selector.rawValue,
                    UnsafeRawPointer(inputPtr),
                    outSize,
                    UnsafeMutableRawPointer(outputPtr),
                    &outSize
                )
            }
        }
        return ioResult == kIOReturnSuccess ? output : nil
    }

    private static func keyData(for key: String) -> SMCKeyData {
        var data = SMCKeyData()
        data.key = fourCharCode(from: key)
        return data
    }

    /// Converts "TC0P" to a FourCharCode-style UInt32.
    private static func fourCharCode(from key: String) -> UInt32 {
        var code: UInt32 = 0
        for scalar in key.unicodeScalars.prefix(4) {
            code = (code << 8) | UInt32(scalar.value & 0xFF)
        }
        return code
    }

    /// Key info plus the firmware's result byte (0 = success).
    private static func keyInfo(
        for key: String
    ) -> (dataSize: UInt32, dataType: UInt32, result: UInt8)? {
        var request = keyData(for: key)
        request.data8 = Command.readKeyInfo.rawValue
        guard let output = call(.handleYPCEvent, &request) else { return nil }
        return (
            dataSize: output.keyInfo.dataSize,
            dataType: output.keyInfo.dataType,
            result: output.result
        )
    }

    private static func readKey(_ key: String) -> (KeyInfo, [UInt8])? {
        guard let info = keyInfo(for: key),
              info.result == 0,
              info.dataSize > 0,
              info.dataSize <= UInt32(SMCBytes.byteCount)
        else { return nil }
        var read = keyData(for: key)
        read.data8 = Command.readBytes.rawValue
        read.keyInfo.dataSize = info.dataSize
        guard let output = call(.handleYPCEvent, &read),
              output.result == 0
        else { return nil }
        let bytes = (0..<Int(info.dataSize)).map { output.bytes.byte(at: $0) }
        return (KeyInfo(dataSize: info.dataSize, dataType: info.dataType), bytes)
    }

    /// Byte size of the kernel request struct (must match C layout: 80).
    public static var keyDataSize: Int { MemoryLayout<SMCKeyData>.size }

    /// Debug helper: raw key info as
    /// "dataSize=.. dataType=0x.. result=.. bytes=..".
    public static func debugInfo(forKey key: String) -> String {
        guard let info = keyInfo(for: key) else { return "open/read failed" }
        var text = String(
            format: "dataSize=%u dataType=0x%08x result=%u",
            info.dataSize,
            info.dataType,
            info.result
        )
        if let (_, bytes) = readKey(key) {
            let hex = bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
            text += " bytes=\(hex)"
        }
        return text
    }

    // MARK: - Payload decoding

    /// Decodes an SMC "flt " payload (IEEE-754 single precision,
    /// little-endian). Used by Apple-Silicon firmware, e.g. for fan speed.
    public static func floatValue(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 4 else { return nil }
        let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
            | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        let value = Double(Float(bitPattern: bits))
        return value.isFinite ? value : nil
    }

    /// Decodes an SMC "fpe2" payload (unsigned 14.2 fixed point,
    /// big-endian). Used by Intel firmware, e.g. for fan speed.
    public static func fixedPointValue(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 2 else { return nil }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return Double(raw) / 4.0
    }

    /// Returns a Celsius value for the given SMC key, e.g. "TC0P".
    public static func temperature(forKey key: String) -> Double? {
        guard let (info, bytes) = readKey(key) else { return nil }
        switch info.dataType {
        case typeFlt:
            return floatValue(bytes)
        case typeSp78:
            return signedFixedPointValue(bytes)
        default:
            return nil
        }
    }

    /// Decodes an "sp78" payload (signed 8.8 fixed point, big-endian).
    private static func signedFixedPointValue(_ bytes: [UInt8]) -> Double? {
        guard bytes.count >= 2 else { return nil }
        let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        return Double(raw) / 256.0
    }

    // MARK: - Fans

    /// Number of keys the firmware exposes ("#KEY"), or nil when the key
    /// cannot be read. Unlike `fanCount()` this key exists on both fanless
    /// and fanned Macs, so it works as an SMC liveness probe.
    public static func keyCount() -> Int? {
        guard let (info, bytes) = readKey("#KEY") else { return nil }
        switch info.dataType {
        case typeUi32:
            guard bytes.count >= 4 else { return nil }
            return Int(
                UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16
                    | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            )
        case typeUi16:
            guard bytes.count >= 2 else { return nil }
            return Int(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        default:
            return nil
        }
    }

    /// Number of fans the firmware reports, or nil when the key cannot be
    /// read. Zero means the Mac really is fanless.
    public static func fanCount() -> Int? {
        guard let (info, bytes) = readKey("FNum") else { return nil }
        switch info.dataType {
        case typeUi8:
            return bytes.first.map { Int($0) }
        case typeUi16:
            guard bytes.count >= 2 else { return nil }
            return Int(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        default:
            return nil
        }
    }

    /// Current RPM of fan `index` ("F0Ac"-style key). Apple-Silicon firmware
    /// publishes fan speed as "flt ", Intel firmware as "fpe2".
    public static func fanRPM(_ index: Int) -> Double? {
        guard index >= 0,
              let (info, bytes) = readKey("F\(index)Ac")
        else { return nil }
        switch info.dataType {
        case typeFlt:
            return floatValue(bytes)
        case typeFpe2:
            return fixedPointValue(bytes)
        default:
            return nil
        }
    }
}
