import AppKit
import MiniRules

extension FaviconTone {
    static func of(_ image: NSImage) -> FaviconTone {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return FaviconTone(luminance: 0, coverage: 0) }
        return measure(premultipliedRGBA: DominantColor.pixels(of: cgImage).flatMap { [$0.red, $0.green, $0.blue, $0.alpha] })
    }
}

enum DominantColor {
    struct Pixel: Equatable {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    static let sampleSide = 24

    static func of(_ image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return color(of: pixels(of: cgImage))
    }

    static func pixels(of image: CGImage) -> [Pixel] {
        let side = sampleSide
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return [] }
        return stride(from: 0, to: bytes.count, by: 4).map { Pixel(red: bytes[$0], green: bytes[$0 + 1], blue: bytes[$0 + 2], alpha: bytes[$0 + 3]) }
    }

    static func color(of pixels: [Pixel]) -> NSColor? {
        var weights: [Int: Double] = [:]
        var sums: [Int: (red: Double, green: Double, blue: Double, count: Double)] = [:]
        for pixel in pixels where pixel.alpha >= 128 {
            let alpha = Double(pixel.alpha) / 255
            let red = min(Double(pixel.red) / 255 / alpha, 1)
            let green = min(Double(pixel.green) / 255 / alpha, 1)
            let blue = min(Double(pixel.blue) / 255 / alpha, 1)
            let maximum = max(red, green, blue)
            let minimum = min(red, green, blue)
            let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
            let bucket = Int(red * 7.99) << 6 | Int(green * 7.99) << 3 | Int(blue * 7.99)
            let vividness = maximum < 0.12 ? 0.05 : 0.1 + saturation
            weights[bucket, default: 0] += vividness
            let sum = sums[bucket] ?? (0, 0, 0, 0)
            sums[bucket] = (sum.red + red, sum.green + green, sum.blue + blue, sum.count + 1)
        }
        guard let best = weights.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) })?.key,
              let sum = sums[best] else { return nil }
        return NSColor(srgbRed: sum.red / sum.count, green: sum.green / sum.count, blue: sum.blue / sum.count, alpha: 1)
    }
}
