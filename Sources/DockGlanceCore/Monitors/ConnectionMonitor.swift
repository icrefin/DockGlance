import CoreWLAN
import Darwin
import SystemConfiguration

/// Describes the active network link: Wi-Fi (with SSID and band) or wired.
public struct ConnectionInfo: Sendable, Equatable {
    /// Wi-Fi network name; nil when not on Wi-Fi.
    public let ssid: String?
    /// Band label ("2.4 GHz" / "5 GHz"); nil when not on Wi-Fi.
    public let band: String?
    /// Interface name (e.g. "en0"); the wired interface when on Ethernet.
    public let interfaceName: String?
    /// True when the active link is wired Ethernet.
    public let isWired: Bool
    /// Local (LAN) IPv4 address of the active link; nil when the link is
    /// down or carries no IPv4 address.
    public let lanIP: String?

    public static let offline = ConnectionInfo(
        ssid: nil, band: nil, interfaceName: nil, isWired: false, lanIP: nil
    )

    /// Short primary text for the tile (SSID, "Wired", "Wi-Fi", "Offline").
    public var summary: String {
        if let ssid { return ssid }
        if isWired { return "Wired" }
        if interfaceName != nil { return "Wi-Fi" }
        return "Offline"
    }

    /// Detail line for the tile's tooltip ("WiFi · 5 GHz", "Wired · en0").
    public var detail: String {
        if ssid != nil, let band { return "WiFi · \(band)" }
        if isWired, let name = interfaceName { return "Wired · \(name)" }
        if let name = interfaceName { return "Wi-Fi · \(name)" }
        return "No connection"
    }
}

/// Samples the active connection via CoreWLAN (Wi-Fi) with a getifaddrs
/// fallback for wired links. Must be used on the main thread (CoreWLAN).
@MainActor
public final class ConnectionMonitor {
    public init() {}

    public func sample() -> ConnectionInfo {
        // A fresh CWWiFiClient (rather than .shared(), which caches its
        // interface) so the SSID reflects a recent network change.
        let wifi = CWWiFiClient().interface()
        if let ssid = wifi?.ssid(), !ssid.isEmpty,
           let channel = wifi?.wlanChannel() {
            let name = wifi?.interfaceName
            return ConnectionInfo(
                ssid: ssid,
                band: bandLabel(for: channel.channelBand),
                interfaceName: name,
                isWired: false,
                lanIP: name.flatMap(ipv4Address(of:))
            )
        }
        // No readable SSID (e.g. location permission not granted yet):
        // fall back to the active interface's hardware type.
        if let name = activeInterface() {
            return ConnectionInfo(
                ssid: nil,
                band: nil,
                interfaceName: name,
                isWired: interfaceKind(name) == .wired,
                lanIP: ipv4Address(of: name)
            )
        }
        return .offline
    }

    private enum LinkKind { case wired, wifi, unknown }

    private func bandLabel(for band: CWChannelBand) -> String {
        switch band {
        case .band2GHz: return "2.4 GHz"
        case .band5GHz: return "5 GHz"
        default: return "\(band.rawValue) GHz"
        }
    }

    /// First live "en*" interface carrying an IPv4 address.
    private func activeInterface() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return nil }
        defer { freeifaddrs(head) }

        var cursor = head
        while true {
            let entry = cursor.pointee
            if entry.ifa_addr?.pointee.sa_family == UInt8(AF_INET),
               entry.ifa_flags & UInt32(IFF_UP | IFF_RUNNING) != 0 {
                let name = String(cString: entry.ifa_name)
                if name.hasPrefix("en") { return name }
            }
            guard let next = entry.ifa_next else { break }
            cursor = next
        }
        return nil
    }

    /// Numeric IPv4 address bound to `name`, e.g. "192.168.1.42"; nil when
    /// the interface is down or has no IPv4 address (IPv6-only links).
    private func ipv4Address(of name: String) -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return nil }
        defer { freeifaddrs(head) }

        var cursor = head
        while true {
            let entry = cursor.pointee
            if String(cString: entry.ifa_name) == name,
               let address = entry.ifa_addr,
               address.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let status = getnameinfo(
                    address, socklen_t(address.pointee.sa_len),
                    &host, socklen_t(host.count),
                    nil, 0, NI_NUMERICHOST
                )
                if status == 0 { return String(cString: host) }
            }
            guard let next = entry.ifa_next else { break }
            cursor = next
        }
        return nil
    }

    /// Classifies an "en*" interface by its hardware port type.
    private func interfaceKind(_ name: String) -> LinkKind {
        guard let interfaces =
            SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]
        else { return .unknown }
        for interface in interfaces {
            guard let bsdRef = SCNetworkInterfaceGetBSDName(interface) else {
                continue
            }
            let bsdName = bsdRef as String
            guard bsdName == name,
                  let typeRef = SCNetworkInterfaceGetInterfaceType(interface)
            else { continue }
            let type = typeRef as String
            if type == kSCNetworkInterfaceTypeEthernet as String {
                return .wired
            }
            if type == kSCNetworkInterfaceTypeIEEE80211 as String {
                return .wifi
            }
            continue
        }
        return .unknown
    }
}
