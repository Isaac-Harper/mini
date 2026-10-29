import Foundation

public struct FaviconTone: Equatable, Sendable {
    public enum Backdrop: Sendable {
        case dark
        case light
    }

    public let luminance: Double
    public let coverage: Double

    public static let minimumCoverage = 0.05
    public static let darkThreshold = 0.12
    public static let lightThreshold = 0.8

    public init(luminance: Double, coverage: Double) {
        self.luminance = luminance
        self.coverage = coverage
    }

    public static func measure(premultipliedRGBA bytes: [UInt8]) -> FaviconTone {
        precondition(bytes.count % 4 == 0, "RGBA bytes come in fours")
        var alphaTotal = 0.0
        var weightedLuminance = 0.0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Double(bytes[index + 3]) / 255
            guard alpha > 0 else { continue }
            func linear(_ byte: UInt8) -> Double {
                let value = min(Double(byte) / 255 / alpha, 1)
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            let luminance = 0.2126 * linear(bytes[index]) + 0.7152 * linear(bytes[index + 1]) + 0.0722 * linear(bytes[index + 2])
            alphaTotal += alpha
            weightedLuminance += luminance * alpha
        }
        let pixelCount = Double(bytes.count / 4)
        guard alphaTotal > 0, pixelCount > 0 else { return FaviconTone(luminance: 0, coverage: 0) }
        return FaviconTone(luminance: weightedLuminance / alphaTotal, coverage: alphaTotal / pixelCount)
    }

    public func needsBackingPlate(on backdrop: Backdrop) -> Bool {
        guard coverage >= Self.minimumCoverage else { return false }
        switch backdrop {
        case .dark: return luminance < Self.darkThreshold
        case .light: return luminance > Self.lightThreshold
        }
    }
}
