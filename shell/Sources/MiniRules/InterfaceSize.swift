import Foundation

public enum InterfaceSize {
    public static let scales: [Double] = [0.85, 0.92, 1, 1.08, 1.17, 1.25]
    public static let actualLevel = 2

    public static func level(stored: Int?) -> Int {
        guard let stored else { return actualLevel }
        return min(max(stored, 0), scales.count - 1)
    }

    public static func larger(than level: Int) -> Int {
        min(level + 1, scales.count - 1)
    }

    public static func smaller(than level: Int) -> Int {
        max(level - 1, 0)
    }

    public static func scaled(_ value: Double, by scale: Double) -> Double {
        (value * scale * 2).rounded() / 2
    }

    public static func sidebarWidth(_ width: Double, from oldScale: Double, to newScale: Double, minimum: Double, maximum: Double) -> Double {
        min(max(scaled(width / oldScale, by: newScale), minimum), maximum)
    }
}
