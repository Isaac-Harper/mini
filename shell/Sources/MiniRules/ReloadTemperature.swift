import Foundation

public enum ReloadTemperature: Equatable, Sendable {
    case plain
    case cold
    case warm
}

public struct ColdReload: Equatable, Sendable {
    public let url: String
    public let date: Date

    public init(url: String, date: Date) {
        self.url = url
        self.date = date
    }
}

public enum ReloadTemperatures {
    public static let warmWindow: TimeInterval = 600
    public static let plainHold: TimeInterval = 1.5
    public static let labeledHold: TimeInterval = 2

    public static func reload(ignoringCache: Bool, url: String, at date: Date,
                              after lastColdReload: ColdReload?) -> (temperature: ReloadTemperature, remembered: ColdReload?) {
        if ignoringCache {
            return (.cold, ColdReload(url: url, date: date))
        }
        guard let lastColdReload, lastColdReload.url == url, date >= lastColdReload.date,
              date.timeIntervalSince(lastColdReload.date) <= warmWindow else { return (.plain, nil) }
        return (.warm, nil)
    }

    public static func label(milliseconds: Double, temperature: ReloadTemperature) -> String {
        let duration = DurationText.milliseconds(milliseconds)
        switch temperature {
        case .plain: return duration
        case .cold: return "cold \(duration)"
        case .warm: return "warm \(duration)"
        }
    }

    public static func hold(for temperature: ReloadTemperature) -> TimeInterval {
        temperature == .plain ? plainHold : labeledHold
    }
}
