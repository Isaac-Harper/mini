import CMiniCore
import Foundation
import MiniRules
import Network

@MainActor
final class HoverPreloader {
    private static let dwell: TimeInterval = 0.15
    private static let enabledKey = "PreloadsOnHover"

    var isEnabled = UserDefaults.standard.object(forKey: HoverPreloader.enabledKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { cancel() }
        }
    }

    private weak var preloadedTab: Tab?
    private var preloadedURL: String?
    private var generation = 0
    private var isNetworkCostly = false
    private let pathMonitor = NWPathMonitor()

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let isCostly = path.isExpensive || path.isConstrained
            Task { @MainActor in self?.isNetworkCostly = isCostly }
        }
        pathMonitor.start(queue: DispatchQueue(label: "dev.isaacharper.mini.network-path"))
    }

    func hoverChanged(_ tab: Tab, url: String) {
        generation += 1
        guard !url.isEmpty else {
            cancel()
            return
        }
        guard url != preloadedURL || tab !== preloadedTab else { return }
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell) { [weak self, weak tab] in
            MainActor.assumeIsolated {
                guard let self, let tab, self.generation == current else { return }
                self.preload(url, in: tab)
            }
        }
    }

    func cancel() {
        let tab = preloadedTab
        preloadedTab = nil
        preloadedURL = nil
        guard let tab, tab.hasBrowser else { return }
        "".withCString { mini_browser_preload(tab.id, $0) }
    }

    private func preload(_ url: String, in tab: Tab) {
        guard isEnabled, tab.hasBrowser, !ProcessInfo.processInfo.isLowPowerModeEnabled, !isNetworkCostly,
              HoverPreload.shouldPreload(url, from: tab.url, registrableDomain: URLInput.registrableDomain) else { return }
        cancel()
        preloadedTab = tab
        preloadedURL = url
        url.withCString { mini_browser_preload(tab.id, $0) }
    }
}
