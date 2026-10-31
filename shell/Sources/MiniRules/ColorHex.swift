import Foundation

public enum ColorHex {
    public static func string(red: Double, green: Double, blue: Double) -> String {
        let channels = [red, green, blue].map { String(format: "%02X", Int((min(max($0, 0), 1) * 255).rounded())) }
        return "#" + channels.joined()
    }
}
