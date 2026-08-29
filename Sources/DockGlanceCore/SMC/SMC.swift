import Foundation
import IOKit

/// Minimal userspace bridge to the "AppleSMC" driver via IOKit.
///
/// The key data structure must byte-match the kernel's `SMCKeyData_t`.
/// It is made only of fixed-size stored properties, which follow the same
/// layout rules as C structs.
///
/// IOKit reads are safe off the main thread; SMC is called from
/// `SensorReader`'s background executor.
public enum SMC {
    private static let serviceName = "AppleSMC"
    // Accessed only from SensorReader's serial executor.
    private nonisolated(unsafe) static var connection: io_connect_t = 0
    private nonisolated(unsafe) static var isOpen = false

    /// "flt " and "sp78" SMC type tags.
    private static let typeFlt: UInt32 = 0x666C7420
    private static let typeSp78: UInt32 = 0x73703738
    private static let typeUi8: UInt32 = 0x75693820 // "ui8 "
    private static let typeFpe2: UInt32 = 0x66706532 // "fpe2"

    private enum Selector: UInt32 {
        case readBytes = 1
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

        var count: Int { MemoryLayout<SMCBytes>.size }

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
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        isOpen = result == kIOReturnSuccess
        return isOpen
    }

    private static func call(
        _ selector: Selector,
        _ input: inout SMCKeyData
    ) -> SMCKeyData? {
        guard ensureOpen() else { return nil }
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

    private static func readKey(_ key: String) -> (KeyInfo, [UInt8])? {
        var input = keyData(for: key)
        guard let infoData = call(.readKeyInfo, &input),
              infoData.keyInfo.dataSize > 0
        else { return nil }
        var read = keyData(for: key)
        read.keyInfo.dataSize = infoData.keyInfo.dataSize
        guard let output = call(.readBytes, &read) else { return nil }
        let info = KeyInfo(
            dataSize: infoData.keyInfo.dataSize,
            dataType: infoData.keyInfo.dataType
        )
        let bytes = (0..<Int(info.dataSize)).map { output.bytes.byte(at: $0) }
        return (info, bytes)
    }

    /// Byte size of the kernel request struct (must match C layout: 80).
    public static var keyDataSize: Int { MemoryLayout<SMCKeyData>.size }

    /// Debug helper: raw key info as "dataSize=.. dataType=0x.. result=..".
    public static func debugInfo(forKey key: String) -> String {
        var input = keyData(for: key)
        guard let infoData = call(.readKeyInfo, &input) else {
            return "open/read failed"
        }
        return String(
            format: "dataSize=%u dataType=0x%08x result=%u",
            infoData.keyInfo.dataSize,
            infoData.keyInfo.dataType,
            infoData.result
        )
    }

    /// Returns a Celsius value for the given SMC key, e.g. "TC0P".
    public static func temperature(forKey key: String) -> Double? {
        guard let (info, bytes) = readKey(key) else { return nil }
        switch info.dataType {
        case typeFlt:
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8
                | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case typeSp78:
            guard bytes.count >= 2 else { return nil }
            let whole = Double(Int8(bitPattern: bytes[0]))
            let fraction = Double(bytes[1]) / 256.0
            return whole + fraction
        default:
            return nil
        }
    }

    /// Number of fans the SMC exposes (0 on fanless machines).
    public static func fanCount() -> Int {
        guard let (info, bytes) = readKey("FNum"),
              info.dataType == typeUi8, !bytes.isEmpty
        else { return 0 }
        return Int(bytes[0])
    }

    /// Current RPM of fan `index` ("F0Ac"-style key), fpe2 fixed point.
    public static func fanRPM(_ index: Int) -> Double? {
        guard index >= 0,
              let (info, bytes) = readKey("F\(index)Ac"),
              info.dataType == typeFpe2, bytes.count >= 2
        else { return nil }
        let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
        return Double(raw) / 4.0
    }
}