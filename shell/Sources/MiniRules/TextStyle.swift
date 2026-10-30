import Foundation

public struct ComputedTextStyle: Codable, Equatable, Sendable {
    public let fontFamily: String
    public let fontSize: String
    public let lineHeight: String
    public let fontWeight: String
    public let letterSpacing: String
    public let color: String
    public let textTransform: String

    public init(fontFamily: String, fontSize: String, lineHeight: String, fontWeight: String, letterSpacing: String, color: String, textTransform: String) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.fontWeight = fontWeight
        self.letterSpacing = letterSpacing
        self.color = color
        self.textTransform = textTransform
    }
}

public enum TextStyle {
    public static func block(_ style: ComputedTextStyle) -> String? {
        guard let color = oklch(fromComputedColor: style.color) else { return nil }
        var declarations = [
            "font-family: \(fontFamilyStack(style.fontFamily));",
            "font-size: \(style.fontSize);",
            "line-height: \(style.lineHeight);",
            "font-weight: \(style.fontWeight);",
            "letter-spacing: \(style.letterSpacing);",
            "color: \(color);",
        ]
        if style.textTransform != "none" {
            declarations.append("text-transform: \(style.textTransform);")
        }
        return declarations.joined(separator: "\n")
    }

    public static func fontFamilyStack(_ computed: String) -> String {
        computed.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    public static func oklch(fromComputedColor text: String) -> String? {
        guard let (red, green, blue, alpha) = parseRGB(text) else { return nil }
        let (lightness, chroma, hue) = oklchComponents(red: red, green: green, blue: blue)
        var result = "oklch(\(format(lightness, places: 2)) \(format(chroma, places: 2)) \(format(hue, places: 0))"
        if alpha < 1 {
            result += " / \(format(alpha, places: 2))"
        }
        return result + ")"
    }

    static func parseRGB(_ text: String) -> (Double, Double, Double, Double)? {
        let lowered = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard lowered.hasPrefix("rgb"), let open = lowered.firstIndex(of: "("), lowered.hasSuffix(")") else { return nil }
        let inner = lowered[lowered.index(after: open)..<lowered.index(before: lowered.endIndex)]
        let parts = inner.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }
        let channels = parts.prefix(3).compactMap { Double($0) }
        guard channels.count == 3, channels.allSatisfy({ (0...255).contains($0) }) else { return nil }
        var alpha = 1.0
        if parts.count == 4 {
            guard let value = parts[3].hasSuffix("%") ? Double(parts[3].dropLast()).map({ $0 / 100 }) : Double(parts[3]), (0...1).contains(value) else { return nil }
            alpha = value
        }
        return (channels[0] / 255, channels[1] / 255, channels[2] / 255, alpha)
    }

    static func oklchComponents(red: Double, green: Double, blue: Double) -> (Double, Double, Double) {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let r = linear(red), g = linear(green), b = linear(blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bAxis = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let chroma = (a * a + bAxis * bAxis).squareRoot()
        var hue = atan2(bAxis, a) * 180 / .pi
        if hue < 0 { hue += 360 }
        return (min(max(lightness, 0), 1), chroma < 0.0005 ? 0 : chroma, chroma < 0.0005 ? 0 : hue)
    }

    private static func format(_ value: Double, places: Int) -> String {
        let scale = pow(10, Double(places))
        let rounded = (value * scale).rounded() / scale
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.\(places)f", rounded).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}
