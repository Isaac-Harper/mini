import Foundation

public enum PageWidth {
    public static let detents: [Double] = [375, 768, 1024, 1280]
    public static let minimum: Double = 320
    public static let snapDistance: Double = 6

    public static func dragged(to width: Double, fullWidth: Double) -> Double? {
        let clamped = min(max(width, min(minimum, fullWidth)), fullWidth)
        if clamped >= fullWidth - snapDistance { return nil }
        if let detent = detents.first(where: { $0 < fullWidth && abs(clamped - $0) <= snapDistance }) { return detent }
        return clamped.rounded()
    }

    public static func displayed(_ width: Double?, fullWidth: Double) -> Double? {
        guard let width, width < fullWidth else { return nil }
        return max(width, min(minimum, fullWidth))
    }

    public static func detent(at width: Double?) -> Double? {
        guard let width, detents.contains(width) else { return nil }
        return width
    }
}
