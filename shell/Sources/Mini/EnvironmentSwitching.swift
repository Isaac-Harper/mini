import AppKit
import CMiniCore
import MiniRules

struct EnvironmentScrollRestore {
    let fraction: Double
    var hasStartedLoading: Bool
}

struct DeploymentEnvironmentsCache {
    let address: String
    let space: String
    let revision: Int
    let environments: [DeploymentEnvironment]
}

private final class EnvironmentChoice {
    weak var tab: Tab?
    let environment: DeploymentEnvironment

    init(tab: Tab, environment: DeploymentEnvironment) {
        self.tab = tab
        self.environment = environment
    }
}

extension ShellController {
    private static let recentHistoryLimit = 5_000
    private static let projectSearchLimit = 200
    private static let scrollReadTimeout: TimeInterval = 0.3

    static func switchTitle(to kind: DeploymentEnvironment.Kind) -> String {
        switch kind {
        case .local: "Switch to Local"
        case .preview: "Switch to Preview"
        case .production: "Switch to Production"
        }
    }

    func deploymentEnvironments(of tab: Tab) -> [DeploymentEnvironment] {
        guard HistoryLibrary.isRecordable(tab.url), let host = URLInput.host(of: tab.url)?.lowercased() else { return [] }
        let spaceIdentifier = (space(containing: tab.id) ?? currentSpace).id
        let historyStore = history.store(forSpace: spaceIdentifier)
        if let cache = deploymentEnvironmentsCache, cache.address == tab.url, cache.space == spaceIdentifier, cache.revision == historyStore.revision {
            return cache.environments
        }
        let projectTerms = PreviewDeployment.of(host: host).map { [$0.project] } ?? PreviewDeployment.productionProjects(ofHost: host, registrableDomain: URLInput.registrableDomain)
        let entries = historyStore.recent(limit: Self.recentHistoryLimit) + projectTerms.flatMap { historyStore.search($0, limit: Self.projectSearchLimit) }
        let visitedPages = entries.map { VisitedPage(url: $0.url, title: $0.title, lastVisit: $0.lastVisit) }
        let environments = DeploymentEnvironments.of(address: tab.url, visitedPages: visitedPages, registrableDomain: URLInput.registrableDomain)
        deploymentEnvironmentsCache = DeploymentEnvironmentsCache(address: tab.url, space: spaceIdentifier, revision: historyStore.revision, environments: environments)
        return environments
    }

    @objc func switchEnvironment(_ sender: Any?) {
        guard keyLittleWindow == nil, let tab = store.selectedTab, let target = DeploymentEnvironments.next(in: deploymentEnvironments(of: tab)) else { return }
        switchEnvironment(of: tab, to: target)
    }

    func showEnvironmentMenu(for tab: Tab, under anchor: NSView) {
        vitalsPopover.close()
        let environments = deploymentEnvironments(of: tab)
        let menu = NSMenu()
        menu.autoenablesItems = false
        let ages = RelativeDateTimeFormatter()
        var listedKind: DeploymentEnvironment.Kind?
        for environment in environments {
            if environment.kind != listedKind {
                menu.addItem(.sectionHeader(title: Self.sectionTitle(of: environment.kind)))
                listedKind = environment.kind
            }
            let item = NSMenuItem(title: environment.displayHost, action: #selector(environmentChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = EnvironmentChoice(tab: tab, environment: environment)
            item.subtitle = environment.lastVisit.map { "Visited \(ages.localizedString(for: $0, relativeTo: Date()))" }
            item.state = environment.isCurrent ? .on : .off
            item.isEnabled = !environment.isCurrent
            menu.addItem(item)
        }
        if environments.count < 2 {
            let item = NSMenuItem(title: "No other environments in this space\u{2019}s history", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: anchor.isFlipped ? anchor.bounds.height + 4 : -4), in: anchor)
    }

    func scrollFractionReceived(_ identifier: MiniTabId, fraction: Double) {
        guard let tab = liveTab(identifier), let address = tab.pendingEnvironmentAddress else { return }
        finishEnvironmentSwitch(of: tab, to: address, scrollFraction: fraction)
    }

    func environmentLoadingChanged(_ tab: Tab, isLoading: Bool) {
        guard var restore = tab.environmentScrollRestore else { return }
        if isLoading {
            restore.hasStartedLoading = true
            tab.environmentScrollRestore = restore
            return
        }
        guard restore.hasStartedLoading else { return }
        tab.environmentScrollRestore = nil
        if tab.hasBrowser {
            mini_browser_restore_scroll_fraction(tab.id, restore.fraction)
        }
    }

    @objc private func environmentChosen(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? EnvironmentChoice, let tab = choice.tab, tab === store.selectedTab else { return }
        switchEnvironment(of: tab, to: choice.environment)
    }

    private func switchEnvironment(of tab: Tab, to environment: DeploymentEnvironment) {
        guard let address = DeploymentEnvironments.address(tab.url, movedTo: environment) else { return }
        guard tab.hasBrowser else {
            navigate(tab, to: address)
            return
        }
        tab.pendingEnvironmentAddress = address
        mini_browser_request_scroll_fraction(tab.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.scrollReadTimeout) { [weak self, weak tab] in
            MainActor.assumeIsolated {
                guard let self, let tab, tab.pendingEnvironmentAddress == address else { return }
                self.finishEnvironmentSwitch(of: tab, to: address, scrollFraction: nil)
            }
        }
    }

    private func finishEnvironmentSwitch(of tab: Tab, to address: String, scrollFraction: Double?) {
        navigate(tab, to: address)
        if let scrollFraction, scrollFraction > 0 {
            tab.environmentScrollRestore = EnvironmentScrollRestore(fraction: scrollFraction, hasStartedLoading: tab.isLoading)
        }
    }

    private static func sectionTitle(of kind: DeploymentEnvironment.Kind) -> String {
        switch kind {
        case .local: "Local"
        case .preview: "Preview"
        case .production: "Production"
        }
    }
}
