import Foundation

public enum WebVitalsMetric: String, CaseIterable, Sendable {
    case largestContentfulPaint = "LCP"
    case interactionToNextPaint = "INP"
    case cumulativeLayoutShift = "CLS"
    case timeToFirstByte = "TTFB"

    var goodLimit: Double {
        switch self {
        case .largestContentfulPaint: 2500
        case .interactionToNextPaint: 200
        case .cumulativeLayoutShift: 0.1
        case .timeToFirstByte: 800
        }
    }

    var poorLimit: Double {
        switch self {
        case .largestContentfulPaint: 4000
        case .interactionToNextPaint: 500
        case .cumulativeLayoutShift: 0.25
        case .timeToFirstByte: 1800
        }
    }
}

public enum WebVitalsRating: Sendable {
    case good
    case needsImprovement
    case poor
}

public struct WebVitals: Equatable, Sendable {
    public var largestContentfulPaint: Double?
    public var interactionToNextPaint: Double?
    public var cumulativeLayoutShift: Double?
    public var timeToFirstByte: Double?

    public init(largestContentfulPaint: Double? = nil, interactionToNextPaint: Double? = nil, cumulativeLayoutShift: Double? = nil, timeToFirstByte: Double? = nil) {
        self.largestContentfulPaint = largestContentfulPaint
        self.interactionToNextPaint = interactionToNextPaint
        self.cumulativeLayoutShift = cumulativeLayoutShift
        self.timeToFirstByte = timeToFirstByte
    }

    public init(reportedLCP: Double, inp: Double, cls: Double, ttfb: Double) {
        self.init(largestContentfulPaint: reportedLCP < 0 ? nil : reportedLCP, interactionToNextPaint: inp < 0 ? nil : inp,
                  cumulativeLayoutShift: cls, timeToFirstByte: ttfb < 0 ? nil : ttfb)
    }

    public func value(of metric: WebVitalsMetric) -> Double? {
        switch metric {
        case .largestContentfulPaint: largestContentfulPaint
        case .interactionToNextPaint: interactionToNextPaint
        case .cumulativeLayoutShift: cumulativeLayoutShift
        case .timeToFirstByte: timeToFirstByte
        }
    }

    public static func rating(of metric: WebVitalsMetric, value: Double) -> WebVitalsRating {
        if value <= metric.goodLimit { return .good }
        if value <= metric.poorLimit { return .needsImprovement }
        return .poor
    }

    public var needsWarning: Bool {
        [WebVitalsMetric.largestContentfulPaint, .cumulativeLayoutShift].contains { metric in
            value(of: metric).map { Self.rating(of: metric, value: $0) == .poor } ?? false
        }
    }

    public static func formatted(_ metric: WebVitalsMetric, value: Double?) -> String {
        guard let value else { return "\u{2026}" }
        if metric == .cumulativeLayoutShift { return String(format: "%.2f", value) }
        return DurationText.milliseconds(value)
    }
}

public enum DurationText {
    public static func milliseconds(_ value: Double) -> String {
        if value < 1000 { return "\(Int(value.rounded()))ms" }
        if value < 10_000 { return String(format: "%.1fs", value / 1000) }
        return "\(Int((value / 1000).rounded()))s"
    }
}
