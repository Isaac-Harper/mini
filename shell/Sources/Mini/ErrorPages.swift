import AppKit
import CMiniCore
import MiniRules
import Network

extension ShellController {
    func showErrorPage(_ identifier: MiniTabId, errorCode: Int32, failedURL: String) {
        guard let tab = liveTab(identifier), let host = URLInput.host(of: failedURL),
              let page = LoadErrorPage(errorCode: errorCode, host: host, isLocalAddress: LocalDevelopment.port(ofLocalAddress: failedURL) != nil) else { return }
        if page.kind == .certificate {
            tab.certificateErrorPage = page
            crashOverlay.refresh()
            return
        }
        let appearance = littleWindow(containing: identifier)?.window?.effectiveAppearance ?? window.effectiveAppearance
        let accent = space(containing: identifier)?.color.accent ?? currentSpace.color.accent
        let html = page.html(symbolDataURL: Self.symbolDataURL(page.symbolName, color: accent),
                             colors: Self.errorPageColors(appearance: appearance, accent: accent), canGoBack: true)
        html.withCString { mini_browser_show_error_page(identifier, $0) }
        if page.kind == .offline {
            offlineRetry.waitForNetwork(tab: identifier, url: failedURL)
        }
    }

    func goBackFromCertificateError() {
        guard let tab = store.selectedTab, tab.hasBrowser else { return }
        mini_browser_go_back(tab.id)
    }

    func networkReturned(_ waiting: [MiniTabId: String]) {
        for (identifier, url) in waiting {
            guard let tab = liveTab(identifier), tab.hasBrowser, tab.url == url else { continue }
            mini_browser_reload(identifier)
        }
    }

    private static func symbolDataURL(_ name: String, color: NSColor) -> String {
        let configuration = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular).applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else {
            preconditionFailure("Missing SF Symbol \(name)")
        }
        let side: CGFloat = 88
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            preconditionFailure("Could not make a symbol bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let size = symbol.size
        let scale = min(side / size.width, side / size.height)
        let drawn = NSSize(width: size.width * scale, height: size.height * scale)
        symbol.draw(in: NSRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2, width: drawn.width, height: drawn.height))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { preconditionFailure("Could not encode a symbol") }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    private static func errorPageColors(appearance: NSAppearance, accent: NSColor) -> LoadErrorPage.Colors {
        var colors: LoadErrorPage.Colors?
        appearance.performAsCurrentDrawingAppearance {
            colors = LoadErrorPage.Colors(background: hex(.windowBackgroundColor), text: hex(.labelColor), secondaryText: hex(.secondaryLabelColor), accent: hex(accent))
        }
        guard let colors else { preconditionFailure("Appearance block did not run") }
        return colors
    }

    private static func hex(_ color: NSColor) -> String {
        guard let color = color.usingColorSpace(.sRGB) else { preconditionFailure("Color has no sRGB form") }
        let alpha = color.alphaComponent
        return String(format: "rgba(%d,%d,%d,%.2f)", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()),
                      Int((color.blueComponent * 255).rounded()), alpha)
    }
}

@MainActor
final class OfflineRetry {
    private let monitor = NWPathMonitor()
    private var waiting: [MiniTabId: String] = [:]
    private var isStarted = false
    var onNetworkReturned: (([MiniTabId: String]) -> Void)?

    func waitForNetwork(tab: MiniTabId, url: String) {
        waiting[tab] = url
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.pathChanged(satisfied: satisfied) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "Mini.OfflineRetry", qos: .utility))
    }

    private func pathChanged(satisfied: Bool) {
        guard satisfied, !waiting.isEmpty else { return }
        let returned = waiting
        waiting = [:]
        onNetworkReturned?(returned)
    }
}
