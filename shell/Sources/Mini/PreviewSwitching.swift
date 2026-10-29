import AppKit
import MiniRules

extension ShellController {
    private static let visitedHostSearchLimit = 200

    func previewCounterpartURL(of tab: Tab) -> String? {
        guard var components = URLComponents(string: tab.url), let host = components.host?.lowercased(),
              ["http", "https"].contains(components.scheme?.lowercased()) else { return nil }
        let searchTerms = PreviewDeployment.of(host: host).map { [$0.project] } ?? PreviewDeployment.productionProjects(ofHost: host)
        guard !searchTerms.isEmpty else { return nil }
        let historyStore = history.store(forSpace: currentSpace.id)
        var visitedHosts: [String] = []
        for term in searchTerms {
            for entry in historyStore.search(term, limit: Self.visitedHostSearchLimit) {
                guard let visitedHost = URL(string: entry.url)?.host()?.lowercased(), visitedHost != host, !visitedHosts.contains(visitedHost) else { continue }
                visitedHosts.append(visitedHost)
            }
        }
        guard let counterpart = PreviewDeployment.counterpart(of: host, amongVisitedHosts: visitedHosts) else { return nil }
        components.host = counterpart
        components.port = nil
        components.scheme = "https"
        return components.string
    }

    @objc func switchPreviewAndProduction(_ sender: Any?) {
        guard keyLittleWindow == nil, let tab = store.selectedTab, let url = previewCounterpartURL(of: tab) else { return }
        navigate(tab, to: url)
    }
}
