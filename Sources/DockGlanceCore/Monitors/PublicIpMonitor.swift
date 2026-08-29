import Foundation

/// A snapshot of the public (egress) IP address and its geo/network
/// details, as reported by ipwho.is. Missing values are "—".
public struct PublicIPInfo: Sendable, Equatable {
    public let ip: String
    public let type: String
    public let flagEmoji: String
    public let country: String
    public let region: String
    public let city: String
    public let postal: String
    public let isp: String
    public let org: String
    public let asn: String
    public let timezone: String

    public static let unavailable = PublicIPInfo(
        ip: "—", type: "—", flagEmoji: "—", country: "—", region: "—",
        city: "—", postal: "—", isp: "—", org: "—", asn: "—", timezone: "—"
    )

    /// "City, Country" for the card (deduped when both are equal, e.g.
    /// Singapore/Singapore); "—" when nothing is known.
    public var location: String {
        var parts = [city, country].filter { !$0.isEmpty && $0 != "—" }
        if parts.count == 2 && parts[0] == parts[1] { parts.removeLast() }
        return parts.isEmpty ? "—" : parts.joined(separator: ", ")
    }

    public init(
        ip: String, type: String, flagEmoji: String, country: String,
        region: String, city: String, postal: String, isp: String,
        org: String, asn: String, timezone: String
    ) {
        self.ip = ip
        self.type = type
        self.flagEmoji = flagEmoji
        self.country = country
        self.region = region
        self.city = city
        self.postal = postal
        self.isp = isp
        self.org = org
        self.asn = asn
        self.timezone = timezone
    }
}

/// Fetches the public IP + location/network details from ipwho.is (no API
/// key) and caches it, refreshing at most every 15 minutes. Silently
/// degrades to `.unavailable` when the request fails.
@MainActor
public final class PublicIpMonitor {
    public private(set) var info = PublicIPInfo.unavailable

    private static let refreshInterval: TimeInterval = 900
    private var lastRefresh = Date.distantPast
    private var isFetching = false

    public init() {}

    public func refreshIfNeeded() {
        guard Date().timeIntervalSince(lastRefresh) >= Self.refreshInterval,
              !isFetching,
              let url = URL(string: "https://ipwho.is/") else { return }
        lastRefresh = Date()
        isFetching = true
        Task {
            defer { isFetching = false }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(IpWhoResponse.self, from: data)
                info = PublicIPInfo(
                    ip: response.ip,
                    type: response.type,
                    flagEmoji: response.flag.emoji,
                    country: response.country,
                    region: response.region,
                    city: response.city,
                    postal: response.postal,
                    isp: response.connection.isp,
                    org: response.connection.org,
                    asn: response.connection.asn.map { "AS\($0)" } ?? "—",
                    timezone: "\(response.timezone.id) (\(response.timezone.utc))"
                )
            } catch {
                info = .unavailable
            }
        }
    }

    private struct IpWhoResponse: Decodable {
        let ip: String
        let type: String
        let country: String
        let region: String
        let city: String
        let postal: String
        let flag: Flag
        let connection: Connection
        let timezone: Timezone

        struct Flag: Decodable { let emoji: String }
        struct Connection: Decodable {
            let asn: Int?
            let org: String
            let isp: String
        }
        struct Timezone: Decodable { let id: String; let utc: String }
    }
}