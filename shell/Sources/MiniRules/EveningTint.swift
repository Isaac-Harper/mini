import Foundation

public enum EveningTint {
    public static let easeDuration: TimeInterval = 20 * 60
    public static let coverage: TimeInterval = 24 * 60 * 60

    public static func strength(at time: Date, sunrises: [Date], sunsets: [Date]) -> Double {
        let events = (sunrises.map { (date: $0, isSunset: false) } + sunsets.map { (date: $0, isSunset: true) }).sorted { $0.date < $1.date }
        guard let first = events.first, let last = events.last,
              time >= first.date.addingTimeInterval(-coverage), time <= last.date.addingTimeInterval(coverage)
        else { return 0 }
        if let easing = events.first(where: { abs(time.timeIntervalSince($0.date)) < easeDuration / 2 }) {
            let progress = (time.timeIntervalSince(easing.date) + easeDuration / 2) / easeDuration
            let eased = progress * progress * (3 - 2 * progress)
            return easing.isSunset ? eased : 1 - eased
        }
        if let previous = events.last(where: { $0.date <= time }) {
            return previous.isSunset ? 1 : 0
        }
        return first.isSunset ? 0 : 1
    }
}
