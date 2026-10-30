import Foundation

public enum ScreenshotGeometry {
    public struct Corners: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let topLeft = Corners(rawValue: 1 << 0)
        public static let topRight = Corners(rawValue: 1 << 1)
        public static let bottomLeft = Corners(rawValue: 1 << 2)
        public static let bottomRight = Corners(rawValue: 1 << 3)
        public static let all: Corners = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }

    public static func zoomFactor(level: Double) -> Double {
        pow(1.2, level)
    }

    public static func cssPoint(viewPoint: CGPoint, zoomLevel: Double) -> CGPoint {
        let factor = zoomFactor(level: zoomLevel)
        return CGPoint(x: viewPoint.x / factor, y: viewPoint.y / factor)
    }

    public static func elementCrop(cssRect: CGRect, pixelRatio: Double, imageSize: CGSize) -> CGRect? {
        guard pixelRatio > 0, cssRect.width > 0, cssRect.height > 0 else { return nil }
        let scaled = CGRect(x: cssRect.minX * pixelRatio, y: cssRect.minY * pixelRatio, width: cssRect.width * pixelRatio, height: cssRect.height * pixelRatio)
        let outward = CGRect(x: scaled.minX.rounded(.down), y: scaled.minY.rounded(.down),
                             width: scaled.maxX.rounded(.up) - scaled.minX.rounded(.down), height: scaled.maxY.rounded(.up) - scaled.minY.rounded(.down))
        let visible = outward.intersection(CGRect(origin: .zero, size: imageSize))
        return visible.isNull || visible.width < 1 || visible.height < 1 ? nil : visible
    }

    public static func cardCorners(of frame: CGRect, in cardBounds: CGRect) -> Corners {
        let tolerance = 0.5
        let left = frame.minX <= cardBounds.minX + tolerance
        let right = frame.maxX >= cardBounds.maxX - tolerance
        let top = frame.minY <= cardBounds.minY + tolerance
        let bottom = frame.maxY >= cardBounds.maxY - tolerance
        var corners: Corners = []
        if top, left { corners.insert(.topLeft) }
        if top, right { corners.insert(.topRight) }
        if bottom, left { corners.insert(.bottomLeft) }
        if bottom, right { corners.insert(.bottomRight) }
        return corners
    }

    public static func pixelCornerRadius(points: Double, imagePixelWidth: Double, viewPointWidth: Double) -> Double {
        guard viewPointWidth > 0 else { return 0 }
        return points * imagePixelWidth / viewPointWidth
    }
}
