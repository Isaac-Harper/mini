import AppKit
import CMiniCore

enum PageColorScheme: Int {
    case system
    case light
    case dark

    var engineValue: Int32 {
        switch self {
        case .system: Int32(MINI_COLOR_SCHEME_SYSTEM.rawValue)
        case .light: Int32(MINI_COLOR_SCHEME_LIGHT.rawValue)
        case .dark: Int32(MINI_COLOR_SCHEME_DARK.rawValue)
        }
    }

    var name: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

extension Tab {
    var hasPageAppearanceOverride: Bool { pageColorScheme != .system || pageReducesMotion }

    var pageAppearanceChip: (text: String, help: String)? {
        switch (pageColorScheme, pageReducesMotion) {
        case (.system, false):
            nil
        case (.system, true):
            ("Reduced motion", "This page sees reduced motion. Click to follow the system again.")
        case let (scheme, false):
            (scheme.name, "This page is shown in \(scheme.name.lowercased()) appearance. Click to follow the system again.")
        case let (scheme, true):
            ("\(scheme.name) \u{00B7} Reduced", "This page is shown in \(scheme.name.lowercased()) appearance with reduced motion. Click to follow the system again.")
        }
    }
}

extension ShellController {
    @objc func setPageColorScheme(_ sender: NSMenuItem) {
        guard let tab = commandBrowserTab, let scheme = PageColorScheme(rawValue: sender.tag) else { return }
        pageAppearance.change(tab, colorScheme: scheme, reducesMotion: tab.pageReducesMotion)
    }

    @objc func togglePageReducedMotion(_ sender: Any?) {
        guard let tab = commandBrowserTab else { return }
        pageAppearance.change(tab, colorScheme: tab.pageColorScheme, reducesMotion: !tab.pageReducesMotion)
    }

    func resetPageAppearance(of tab: Tab) {
        guard tab.hasBrowser, tab.hasPageAppearanceOverride else { return }
        pageAppearance.change(tab, colorScheme: .system, reducesMotion: false)
    }

    func validatePageAppearanceItem(_ menuItem: NSMenuItem) -> Bool {
        let tab = commandBrowserTab
        if menuItem.action == #selector(setPageColorScheme(_:)) {
            menuItem.state = tab.map { $0.pageColorScheme.rawValue == menuItem.tag } ?? false ? .on : .off
        } else {
            menuItem.state = tab?.pageReducesMotion == true ? .on : .off
        }
        return tab != nil
    }

    func pageSnapshotReceived(_ identifier: MiniTabId, request: UInt64, image: Data, elementBox: CGRect?, pixelRatio: Double?) {
        if PageScreenshot.isPending(request) {
            screenshotCaptured(identifier, request: request, pngData: image, elementBox: elementBox, pixelRatio: pixelRatio)
        } else {
            pageAppearance.snapshotReceived(identifier, request: request, image: image)
        }
    }
}

@MainActor
final class PageAppearanceTransitions {
    static let snapshotTimeout: TimeInterval = 0.25
    static let paintBeat: TimeInterval = 0.15
    static let fadeDuration: TimeInterval = 0.2

    private unowned let shell: ShellController
    private var pendingSnapshots: [MiniTabId: UInt64] = [:]

    init(shell: ShellController) {
        self.shell = shell
    }

    func change(_ tab: Tab, colorScheme: PageColorScheme, reducesMotion: Bool) {
        tab.pageColorScheme = colorScheme
        tab.pageReducesMotion = reducesMotion
        guard pendingSnapshots[tab.id] == nil else { return }
        guard crossfades(tab) else {
            apply(tab)
            return
        }
        let request = PageSnapshotRequest.next()
        pendingSnapshots[tab.id] = request
        mini_browser_capture_snapshot(tab.id, request, Int32(MINI_CAPTURE_JPEG.rawValue), false, 0, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.snapshotTimeout) { [weak self, weak tab] in
            MainActor.assumeIsolated {
                guard let self, let tab, self.pendingSnapshots[tab.id] == request else { return }
                self.pendingSnapshots[tab.id] = nil
                self.apply(tab)
            }
        }
    }

    func snapshotReceived(_ identifier: MiniTabId, request: UInt64, image: Data) {
        guard pendingSnapshots[identifier] == request else { return }
        pendingSnapshots[identifier] = nil
        guard let tab = shell.liveTab(identifier) ?? shell.littleWindows[identifier]?.tab else { return }
        if crossfades(tab), let snapshot = NSImage(data: image) {
            showOverlay(snapshot, over: tab)
        }
        apply(tab)
    }

    private func crossfades(_ tab: Tab) -> Bool {
        !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && tab.hasBrowser
            && shell.displayedTabs.contains { $0 === tab } && tab.hostView.window === shell.window && !tab.hostView.bounds.isEmpty
    }

    private func apply(_ tab: Tab) {
        guard tab.hasBrowser else { return }
        mini_browser_set_emulated_media(tab.id, tab.pageColorScheme.engineValue, tab.pageReducesMotion)
    }

    private func showOverlay(_ snapshot: NSImage, over tab: Tab) {
        let windowController = shell.windowController!
        let webAreaView = windowController.webAreaView
        let rootView = windowController.rootView
        let overlay = PageSnapshotView()
        overlay.frame = rootView.convert(webAreaView.bounds, from: webAreaView)
        overlay.layer?.cornerRadius = webAreaView.layer?.cornerRadius ?? 0
        overlay.layer?.cornerCurve = .continuous
        overlay.layer?.masksToBounds = true
        let imageLayer = CALayer()
        imageLayer.frame = webAreaView.convert(tab.hostView.bounds, from: tab.hostView)
        imageLayer.contents = snapshot
        imageLayer.contentsGravity = .resize
        overlay.layer?.addSublayer(imageLayer)
        rootView.addSubview(overlay, positioned: .above, relativeTo: windowController.webContentController.cardView)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.paintBeat) {
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = Self.fadeDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    overlay.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated { overlay.removeFromSuperview() }
                })
            }
        }
    }
}

final class PageSnapshotView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
