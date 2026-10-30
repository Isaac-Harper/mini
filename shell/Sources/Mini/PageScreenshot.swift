import AppKit
import CMiniCore
import MiniRules
import SwiftUI

@MainActor
enum PageSnapshotRequest {
    private static var last: UInt64 = 0

    static func next() -> UInt64 {
        last += 1
        return last
    }
}

@MainActor
enum PageScreenshot {
    private struct Pending {
        let viewWidth: CGFloat
        let corners: ScreenshotGeometry.Corners
        let cornerRadius: CGFloat
        let measuresElement: Bool
    }

    private static var pending: [UInt64: Pending] = [:]

    static func isPending(_ request: UInt64) -> Bool {
        pending[request] != nil
    }

    static func capture(_ tab: Tab, in shell: ShellController, elementAt viewPoint: NSPoint?) {
        guard tab.hasBrowser else { return }
        let webAreaView = shell.windowController.webAreaView
        let hostFrame = tab.hostView.frame
        let topLeftFrame = webAreaView.isFlipped
            ? hostFrame : CGRect(x: hostFrame.minX, y: webAreaView.bounds.height - hostFrame.maxY, width: hostFrame.width, height: hostFrame.height)
        let request = PageSnapshotRequest.next()
        pending[request] = Pending(viewWidth: tab.hostView.bounds.width, corners: ScreenshotGeometry.cardCorners(of: topLeftFrame, in: webAreaView.bounds),
                                   cornerRadius: webAreaView.layer?.cornerRadius ?? 0, measuresElement: viewPoint != nil)
        let zoomLevel = SitePreferences.host(of: tab.url).map(shell.sitePreferences.zoomLevel(host:)) ?? 0
        let cssPoint = viewPoint.map { ScreenshotGeometry.cssPoint(viewPoint: $0, zoomLevel: zoomLevel) } ?? .zero
        mini_browser_capture_snapshot(tab.id, request, Int32(MINI_CAPTURE_PNG.rawValue), viewPoint != nil, cssPoint.x, cssPoint.y)
        pressShutter(shell.windowController.pageCardView)
    }

    static func finish(request: UInt64, pngData: Data, elementBox: CGRect?, pixelRatio: Double?) -> (png: Data, image: NSImage)? {
        guard let capture = pending.removeValue(forKey: request), let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let imageSize = CGSize(width: image.width, height: image.height)
        let output: CGImage?
        if capture.measuresElement {
            guard let elementBox, let pixelRatio,
                  let crop = ScreenshotGeometry.elementCrop(cssRect: elementBox, pixelRatio: pixelRatio, imageSize: imageSize) else { return nil }
            output = image.cropping(to: crop)
        } else {
            let radius = ScreenshotGeometry.pixelCornerRadius(points: capture.cornerRadius, imagePixelWidth: imageSize.width, viewPointWidth: capture.viewWidth)
            output = rounded(image, corners: capture.corners, radius: radius)
        }
        guard let output, let png = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]) else { return nil }
        let pointSize = NSSize(width: CGFloat(output.width) / 2, height: CGFloat(output.height) / 2)
        return (png, NSImage(cgImage: output, size: pointSize))
    }

    private static func rounded(_ image: CGImage, corners: ScreenshotGeometry.Corners, radius: Double) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let shape = UnevenRoundedRectangle(topLeadingRadius: corners.contains(.topLeft) ? radius : 0, bottomLeadingRadius: corners.contains(.bottomLeft) ? radius : 0,
                                           bottomTrailingRadius: corners.contains(.bottomRight) ? radius : 0, topTrailingRadius: corners.contains(.topRight) ? radius : 0,
                                           style: .continuous)
        var flip = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
        guard let path = shape.path(in: bounds).cgPath.copy(using: &flip) else { return nil }
        context.addPath(path)
        context.clip()
        context.draw(image, in: bounds)
        return context.makeImage()
    }

    private static func pressShutter(_ cardView: NSView) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = cardView.layer else { return }
        let bounds = cardView.bounds
        let scale: CGFloat = 0.98
        var pressed = CATransform3DMakeTranslation(bounds.width * (1 - scale) / 2, bounds.height * (1 - scale) / 2, 0)
        pressed = CATransform3DScale(pressed, scale, scale, 1)
        let press = CAKeyframeAnimation(keyPath: "transform")
        press.values = [CATransform3DIdentity, pressed, CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
        press.keyTimes = [0, 0.35, 1]
        press.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(controlPoints: 0.2, 1.4, 0.4, 1)]
        press.duration = 0.18
        layer.add(press, forKey: "screenshotShutter")
    }
}

@MainActor
final class ScreenshotThumbnailView: NSView, NSDraggingSource {
    private let image: NSImage
    private let pngData: Data
    private var mouseDownEvent: NSEvent?
    private var temporaryFile: URL?

    init(image: NSImage, pngData: Data, size: NSSize) {
        self.image = image
        self.pngData = pngData
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspect
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityRole(.image)
        setAccessibilityLabel("Screenshot")
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: size.width), heightAnchor.constraint(equalToConstant: size.height)])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent else { return }
        let distance = hypot(event.locationInWindow.x - start.locationInWindow.x, event.locationInWindow.y - start.locationInWindow.y)
        guard distance > 3 else { return }
        mouseDownEvent = nil
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let file = writeTemporaryFile() {
            item.setString(file.absoluteString, forType: .fileURL)
        }
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [draggingItem], event: start, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    private func writeTemporaryFile() -> URL? {
        if let temporaryFile { return temporaryFile }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Mini Screenshots", isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let file = directory.appendingPathComponent("Screenshot \(formatter.string(from: Date())).png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try pngData.write(to: file)
        } catch {
            return nil
        }
        temporaryFile = file
        return file
    }
}

extension ShellController {
    func screenshotCaptured(_ identifier: MiniTabId, request: UInt64, pngData: Data, elementBox: CGRect?, pixelRatio: Double?) {
        guard let result = PageScreenshot.finish(request: request, pngData: pngData, elementBox: elementBox, pixelRatio: pixelRatio) else {
            toast.show("Could Not Copy Screenshot")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(result.png, forType: .png)
        toast.show(card: screenshotToastCard(result.image, pngData: result.png), cornerRadius: LinkPreviewCardView.cornerRadius, duration: 4)
    }

    private func screenshotToastCard(_ image: NSImage, pngData: Data) -> NSView {
        let inset = LinkPreviewCardView.imageInset
        let maximum = NSSize(width: InterfaceScale.scaled(220), height: InterfaceScale.scaled(140))
        let fit = min(maximum.width / max(image.size.width, 1), maximum.height / max(image.size.height, 1), 1)
        let thumbnailSize = NSSize(width: (image.size.width * fit).rounded(), height: (image.size.height * fit).rounded())
        let thumbnail = ScreenshotThumbnailView(image: image, pngData: pngData, size: thumbnailSize)
        let label = NSTextField(labelWithString: "Copied")
        label.font = InterfaceFont.tooltip
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        let card = NSView()
        card.addSubview(thumbnail)
        card.addSubview(label)
        NSLayoutConstraint.activate([
            thumbnail.topAnchor.constraint(equalTo: card.topAnchor, constant: inset),
            thumbnail.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            card.widthAnchor.constraint(greaterThanOrEqualTo: thumbnail.widthAnchor, constant: inset * 2),
            label.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: InterfaceScale.scaled(4)),
            label.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -InterfaceScale.scaled(6)),
            card.widthAnchor.constraint(greaterThanOrEqualTo: label.widthAnchor, constant: inset * 4),
        ])
        let hugging = card.widthAnchor.constraint(equalToConstant: 0)
        hugging.priority = .defaultLow
        hugging.isActive = true
        return card
    }
}
