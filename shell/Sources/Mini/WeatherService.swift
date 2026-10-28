import AppKit
import CoreLocation
import MapKit
import Observation

struct WeatherReading: Codable, Equatable {
    let temperature: Double
    let high: Double
    let low: Double
    let code: Int
    let isDay: Bool
    let place: String?
}

struct WeatherCondition: Equatable {
    let symbolName: String
    let name: String

    static func forCode(_ code: Int, isDay: Bool) -> WeatherCondition {
        func daytime(_ day: String, _ night: String) -> String { isDay ? day : night }
        switch code {
        case 0: return WeatherCondition(symbolName: daytime("sun.max.fill", "moon.stars.fill"), name: "Clear")
        case 1: return WeatherCondition(symbolName: daytime("sun.max.fill", "moon.fill"), name: "Mainly Clear")
        case 2: return WeatherCondition(symbolName: daytime("cloud.sun.fill", "cloud.moon.fill"), name: "Partly Cloudy")
        case 3: return WeatherCondition(symbolName: "cloud.fill", name: "Overcast")
        case 45, 48: return WeatherCondition(symbolName: "cloud.fog.fill", name: "Fog")
        case 51, 53, 55: return WeatherCondition(symbolName: "cloud.drizzle.fill", name: "Drizzle")
        case 56, 57: return WeatherCondition(symbolName: "cloud.sleet.fill", name: "Freezing Drizzle")
        case 61, 63: return WeatherCondition(symbolName: "cloud.rain.fill", name: "Rain")
        case 65: return WeatherCondition(symbolName: "cloud.heavyrain.fill", name: "Heavy Rain")
        case 66, 67: return WeatherCondition(symbolName: "cloud.sleet.fill", name: "Freezing Rain")
        case 71, 73, 75: return WeatherCondition(symbolName: "cloud.snow.fill", name: "Snow")
        case 77: return WeatherCondition(symbolName: "cloud.snow", name: "Snow Grains")
        case 80, 81: return WeatherCondition(symbolName: daytime("cloud.sun.rain.fill", "cloud.moon.rain.fill"), name: "Showers")
        case 82: return WeatherCondition(symbolName: "cloud.heavyrain.fill", name: "Heavy Showers")
        case 85, 86: return WeatherCondition(symbolName: "cloud.snow.fill", name: "Snow Showers")
        case 95: return WeatherCondition(symbolName: "cloud.bolt.rain.fill", name: "Thunderstorm")
        case 96, 99: return WeatherCondition(symbolName: "cloud.bolt.rain.fill", name: "Thunderstorm with Hail")
        default: return WeatherCondition(symbolName: "thermometer.medium", name: "Unknown")
        }
    }
}

private struct OpenMeteoForecast: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let is_day: Int
    }

    struct Daily: Decodable {
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
    }

    let current: Current
    let daily: Daily
}

@MainActor
@Observable
final class WeatherService: NSObject, CLLocationManagerDelegate {
    private(set) var reading: WeatherReading?

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var fetchTask: Task<Void, Never>?

    private static let cacheKey = "WeatherReading"
    private static let refreshInterval: TimeInterval = 30 * 60

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey) {
            reading = try? JSONDecoder().decode(WeatherReading.self, from: data)
        }
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func start() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            forgetReading()
        default:
            locationManager.requestLocation()
        }
    }

    private func forgetReading() {
        reading = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            switch locationManager.authorizationStatus {
            case .notDetermined:
                return
            case .denied, .restricted:
                forgetReading()
            default:
                locationManager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let latitude = (location.coordinate.latitude * 100).rounded() / 100
        let longitude = (location.coordinate.longitude * 100).rounded() / 100
        MainActor.assumeIsolated { fetch(latitude: latitude, longitude: longitude) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}

    private func fetch(latitude: Double, longitude: Double) {
        fetchTask?.cancel()
        let usesFahrenheit = Locale.current.measurementSystem == .us
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
        ] + (usesFahrenheit ? [URLQueryItem(name: "temperature_unit", value: "fahrenheit")] : [])
        guard let url = components?.url else { preconditionFailure("Open-Meteo URL could not be built") }
        fetchTask = Task { @MainActor [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let forecast = try? JSONDecoder().decode(OpenMeteoForecast.self, from: data),
                  let high = forecast.daily.temperature_2m_max.first,
                  let low = forecast.daily.temperature_2m_min.first
            else { return }
            let place = await Self.placeName(latitude: latitude, longitude: longitude)
            guard let self, !Task.isCancelled else { return }
            let reading = WeatherReading(
                temperature: forecast.current.temperature_2m,
                high: high,
                low: low,
                code: forecast.current.weather_code,
                isDay: forecast.current.is_day == 1,
                place: place ?? self.reading?.place
            )
            self.reading = reading
            if let encoded = try? JSONEncoder().encode(reading) {
                UserDefaults.standard.set(encoded, forKey: Self.cacheKey)
            }
        }
    }

    private static func placeName(latitude: Double, longitude: Double) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: latitude, longitude: longitude)),
              let mapItems = try? await request.mapItems
        else { return nil }
        return mapItems.first?.addressRepresentations?.cityName
    }
}
