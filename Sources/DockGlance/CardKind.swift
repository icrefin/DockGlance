import Foundation

/// The dashboard's tiles, in canonical display order. The menu uses this
/// list, so new cards appear in Settings automatically.
enum CardKind: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case temperature
    case disk
    case download
    case upload
    case battery
    case connection
    case publicIP
    case time
    case date
    case weather

    var id: String { rawValue }

    /// Human-readable name shown in the "Cards" settings submenu.
    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .temperature: "Temperature"
        case .disk: "Disk"
        case .download: "Download speed"
        case .upload: "Upload speed"
        case .battery: "Battery"
        case .connection: "Connection (Wi-Fi/Ethernet)"
        case .publicIP: "Public IP"
        case .time: "Time"
        case .date: "Date"
        case .weather: "Weather"
        }
    }

    /// Whether hovering the card reveals a detail pop-up above it.
    var hasPopup: Bool {
        switch self {
        case .cpu, .memory, .temperature, .disk, .download, .upload,
             .battery, .weather, .time, .date, .connection, .publicIP: true
        }
    }
}