import AppKit
import Foundation

/// A snapshot of the display configuration, recorded in profiles at save
/// time and matched against the live configuration when displays change.
/// A profile with a matching mode is applied automatically.
struct DisplayMode: Codable, Equatable {
    enum Mode: String, Codable {
        case builtIn       // only the built-in display is in use
        case extended      // an external display is usable (not mirrored)
        case mirrored      // external display mirrors the built-in
    }

    var mode: Mode
    /// Name of the built-in display, e.g. "Built-in Retina Display".
    var builtInName: String?
    /// Model names of connected external displays, e.g. ["DELL U2720Q"].
    var externalNames: [String]

    /// True when two configurations describe the same display situation
    /// (mode plus the same set of external models — order-insensitive).
    func matches(_ other: DisplayMode) -> Bool {
        mode == other.mode && Set(externalNames) == Set(other.externalNames)
    }

    /// The live configuration: built-in-only, extended (any external that
    /// is not mirrored), or mirrored (externals present but all mirrored).
    @MainActor
    static func current() -> DisplayMode {
        var builtInName: String?
        var externalNames: Set<String> = []
        var anyExternalExtended = false
        var anyExternalMirrored = false

        for screen in NSScreen.screens {
            let name = screen.localizedName
            let rawID = screen.deviceDescription[NSDeviceDescriptionKey(
                "NSScreenNumber")] as? NSNumber
            let displayID = rawID.map { CGDirectDisplayID($0.uint32Value) } ?? 0
            let isBuiltIn = displayID != 0 && CGDisplayIsBuiltin(displayID) != 0
            if isBuiltIn {
                builtInName = name
            } else {
                externalNames.insert(name)
                if displayID != 0, CGDisplayIsInMirrorSet(displayID) != 0 {
                    anyExternalMirrored = true
                } else {
                    anyExternalExtended = true
                }
            }
        }

        let mode: Mode
        if externalNames.isEmpty {
            mode = .builtIn
        } else if anyExternalExtended {
            mode = .extended
        } else if anyExternalMirrored {
            mode = .mirrored
        } else {
            mode = .builtIn
        }
        return DisplayMode(
            mode: mode,
            builtInName: builtInName,
            externalNames: externalNames.sorted()
        )
    }
}