import Foundation
import Testing
import MiniRules

struct ScreenshotGeometryTests {
    @Test func viewPointsBecomeCSSPixelsUnderZoom() {
        #expect(ScreenshotGeometry.cssPoint(viewPoint: CGPoint(x: 120, y: 60), zoomLevel: 0) == CGPoint(x: 120, y: 60))
        let zoomed = ScreenshotGeometry.cssPoint(viewPoint: CGPoint(x: 144, y: 72), zoomLevel: 1)
        #expect(abs(zoomed.x - 120) < 0.0001 && abs(zoomed.y - 60) < 0.0001)
        let zoomedOut = ScreenshotGeometry.cssPoint(viewPoint: CGPoint(x: 100, y: 50), zoomLevel: -1)
        #expect(abs(zoomedOut.x - 120) < 0.0001 && abs(zoomedOut.y - 60) < 0.0001)
    }

    @Test func elementBoxesScaleByThePixelRatioAndRoundOutward() {
        let crop = ScreenshotGeometry.elementCrop(cssRect: CGRect(x: 10.3, y: 20.6, width: 100.2, height: 40), pixelRatio: 2, imageSize: CGSize(width: 2000, height: 1200))
        #expect(crop == CGRect(x: 20, y: 41, width: 201, height: 81))
        let zoomed = ScreenshotGeometry.elementCrop(cssRect: CGRect(x: 10, y: 10, width: 50, height: 50), pixelRatio: 3, imageSize: CGSize(width: 2000, height: 1200))
        #expect(zoomed == CGRect(x: 30, y: 30, width: 150, height: 150))
    }

    @Test func elementBoxesAreClippedToTheVisiblePage() {
        let partly = ScreenshotGeometry.elementCrop(cssRect: CGRect(x: -50, y: 500, width: 200, height: 200), pixelRatio: 2, imageSize: CGSize(width: 2000, height: 1200))
        #expect(partly == CGRect(x: 0, y: 1000, width: 300, height: 200))
        #expect(ScreenshotGeometry.elementCrop(cssRect: CGRect(x: 0, y: 900, width: 100, height: 100), pixelRatio: 2, imageSize: CGSize(width: 2000, height: 1200)) == nil)
        #expect(ScreenshotGeometry.elementCrop(cssRect: CGRect(x: 0, y: 0, width: 0, height: 100), pixelRatio: 2, imageSize: CGSize(width: 2000, height: 1200)) == nil)
    }

    @Test func onlyCornersOnTheCardEdgeAreRounded() {
        let card = CGRect(x: 0, y: 0, width: 1000, height: 700)
        #expect(ScreenshotGeometry.cardCorners(of: card, in: card) == .all)
        #expect(ScreenshotGeometry.cardCorners(of: CGRect(x: 0, y: 0, width: 497, height: 700), in: card) == [.topLeft, .bottomLeft])
        #expect(ScreenshotGeometry.cardCorners(of: CGRect(x: 503, y: 0, width: 497, height: 700), in: card) == [.topRight, .bottomRight])
    }

    @Test func theCornerRadiusFollowsTheImageScale() {
        #expect(ScreenshotGeometry.pixelCornerRadius(points: 18, imagePixelWidth: 2000, viewPointWidth: 1000) == 36)
        #expect(ScreenshotGeometry.pixelCornerRadius(points: 18, imagePixelWidth: 1000, viewPointWidth: 1000) == 18)
    }
}
