import CoreLocation
import Foundation

/// A human-readable weather snapshot for the widget tile.
public struct WeatherInfo: Sendable, Equatable {
    /// Air temperature in Celsius.
    public let temperature: Double?
    /// SF Symbol name describing the condition.
    public let symbol: String?
    /// Condition title ("Clear sky", "Rain", ...).
    public let title: String
    /// Relative humidity in percent, when available.
    public let humidity: Double?
    /// Wind speed in km/h, when available.
    public let windSpeedKmh: Double?
    /// Apparent (feels-like) temperature in Celsius.
    public let apparentTemperature: Double?
    /// Tomorrow's min/max temperature and condition code.
    public let nextDay: NextDayForecast?

    public init(
        temperature: Double?, symbol: String?, title: String,
        humidity: Double? = nil, windSpeedKmh: Double? = nil,
        apparentTemperature: Double? = nil, nextDay: NextDayForecast? = nil
    ) {
        self.temperature = temperature
        self.symbol = symbol
        self.title = title
        self.humidity = humidity
        self.windSpeedKmh = windSpeedKmh
        self.apparentTemperature = apparentTemperature
        self.nextDay = nextDay
    }

    public static let unavailable = WeatherInfo(
        temperature: nil, symbol: nil, title: "—"
    )
}

/// Next-day outlook: extreme temperatures plus condition code (WMO).
public struct NextDayForecast: Sendable, Equatable {
    public let min: Double
    public let max: Double
    public let weatherCode: Int

    public init(min: Double, max: Double, weatherCode: Int) {
        self.min = min
        self.max = max
        self.weatherCode = weatherCode
    }
}

/// A two-line human-readable location: district and city/country.
public struct LocationInfo: Sendable, Equatable {
    /// District/neighbourhood, e.g. "Xuhui".
    public let primary: String?
    /// City (or country when no district), e.g. "Shanghai".
    public let secondary: String?

    public static let unavailable = LocationInfo(primary: nil, secondary: nil)
}

/// Best-effort weather for the current location: CoreLocation for the
/// coordinate (asked once), Open-Meteo (no API key) for conditions.
/// Refreshes at most every 5 minutes; silently degrades to `.unavailable`
/// when the user denies location or the fetch fails. Also reverse-geocodes
/// the coordinate into a location name for the location card.
@MainActor
public final class WeatherMonitor: NSObject, @preconcurrency CLLocationManagerDelegate {
    public private(set) var info = WeatherInfo.unavailable
    public private(set) var location = LocationInfo.unavailable

    private static let refreshInterval: TimeInterval = 300

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var didRequestAuthorization = false
    private var lastRefresh = Date.distantPast

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Fetches weather when due; requests location permission on first call.
    public func refreshIfNeeded() {
        guard Date().timeIntervalSince(lastRefresh) >= Self.refreshInterval
        else { return }
        lastRefresh = Date()

        switch manager.authorizationStatus {
        case .notDetermined:
            if !didRequestAuthorization {
                didRequestAuthorization = true
                manager.requestWhenInUseAuthorization()
            }
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            info = .unavailable
        }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            break
        default:
            info = .unavailable
        }
    }

    public func locationManager(
        _ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        fetch(latitude: location.coordinate.latitude,
              longitude: location.coordinate.longitude)
        reverseGeocode(location.coordinate)
    }

    public func locationManager(
        _ manager: CLLocationManager, didFailWithError error: Error
    ) {
        info = .unavailable
    }

    private func fetch(latitude: Double, longitude: Double) {
        var components = URLComponents(
            string: "https://api.open-meteo.com/v1/forecast"
        )!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m"
            ),
            URLQueryItem(
                name: "daily",
                value: "temperature_2m_max,temperature_2m_min,weather_code"
            ),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components.url else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(
                    OpenMeteoResponse.self, from: data
                )
                let code = response.current.weatherCode
                info = WeatherInfo(
                    temperature: response.current.temperature2m,
                    symbol: Self.symbol(for: code),
                    title: Self.title(for: code),
                    humidity: response.current.relativeHumidity2m,
                    windSpeedKmh: response.current.windSpeed10m,
                    apparentTemperature: response.current.apparentTemperature,
                    nextDay: response.daily.nextDay
                )
            } catch {
                info = .unavailable
            }
        }
    }

    // MARK: - WMO weather code mapping

    private static func title(for code: Int) -> String {
        switch code {
        case 0: "Clear sky"
        case 1, 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Foggy"
        case 51...57: "Drizzle"
        case 61...67: "Rain"
        case 71...77: "Snow"
        case 80...82: "Showers"
        case 85, 86: "Snow showers"
        case 95...99: "Thunderstorm"
        default: "Weather"
        }
    }

    private static func symbol(for code: Int) -> String {
        switch code {
        case 0: "sun.max"
        case 1, 2: "cloud.sun"
        case 3: "cloud"
        case 45, 48: "cloud.fog"
        case 51...57: "cloud.drizzle"
        case 61...67: "cloud.rain"
        case 71...77: "cloud.snow"
        case 80...82: "cloud.rain"
        case 85, 86: "cloud.snow"
        case 95...99: "cloud.bolt.rain"
        default: "cloud"
        }
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(
            latitude: coordinate.latitude, longitude: coordinate.longitude
        )
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            let info = Self.name(for: placemarks?.first)
            Task { @MainActor in self?.location = info }
        }
    }

    /// District on the first line, city (or country) on the second.
    nonisolated private static func name(for placemark: CLPlacemark?) -> LocationInfo {
        guard let placemark else { return .unavailable }
        if let subLocality = placemark.subLocality {
            return LocationInfo(primary: subLocality, secondary: placemark.locality)
        }
        if let locality = placemark.locality {
            return LocationInfo(primary: locality, secondary: placemark.country)
        }
        return .unavailable
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature2m: Double
            let weatherCode: Int
            let relativeHumidity2m: Double?
            let windSpeed10m: Double?
            let apparentTemperature: Double?

            enum CodingKeys: String, CodingKey {
                case temperature2m = "temperature_2m"
                case weatherCode = "weather_code"
                case relativeHumidity2m = "relative_humidity_2m"
                case windSpeed10m = "wind_speed_10m"
                case apparentTemperature = "apparent_temperature"
            }
        }

        struct Daily: Decodable {
            let temperature2mMax: [Double]
            let temperature2mMin: [Double]
            let weatherCode: [Int]

            enum CodingKeys: String, CodingKey {
                case temperature2mMax = "temperature_2m_max"
                case temperature2mMin = "temperature_2m_min"
                case weatherCode = "weather_code"
            }

            /// Tomorrow's outlook (the second of the two forecast days).
            var nextDay: NextDayForecast? {
                guard temperature2mMax.count > 1,
                      temperature2mMin.count > 1,
                      weatherCode.count > 1 else { return nil }
                return NextDayForecast(
                    min: temperature2mMin[1],
                    max: temperature2mMax[1],
                    weatherCode: weatherCode[1]
                )
            }
        }

        let current: Current
        let daily: Daily
    }
}