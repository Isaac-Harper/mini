import CMiniCore
import Foundation
import MiniRules

@MainActor
final class DevServerWait {
    let url: String
    let port: Int
    fileprivate(set) var hasGivenUp = false
    fileprivate var task: Task<Void, Never>?

    init(url: String, port: Int) {
        self.url = url
        self.port = port
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

extension ShellController {
    private static let reconnectBudget: TimeInterval = 60

    func mainFrameLoadFailed(_ identifier: MiniTabId, errorCode: Int32, failedURL: String) {
        guard errorCode == LocalDevelopment.connectionRefusedError, let tab = liveTab(identifier),
              let port = LocalDevelopment.port(ofLocalAddress: failedURL) else { return }
        waitForDevServer(tab, url: failedURL, port: port)
    }

    func waitForDevServer(_ tab: Tab, url: String, port: Int) {
        tab.devServerWait?.cancel()
        let wait = DevServerWait(url: url, port: port)
        tab.devServerWait = wait
        crashOverlay.refresh()
        wait.task = Task { [weak self, weak tab, weak wait] in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            for delay in LocalDevelopment.retryDelays(totalSeconds: Self.reconnectBudget) {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
                guard await LocalServerScanner.answersHTTP(port: port, session: session) else { continue }
                guard let self, let tab, let wait, tab.devServerWait === wait, tab.hasBrowser else { return }
                tab.devServerWait = nil
                self.crashOverlay.refresh()
                url.withCString { mini_browser_load_url(tab.id, $0) }
                return
            }
            guard let self, let tab, let wait, tab.devServerWait === wait else { return }
            wait.hasGivenUp = true
            self.crashOverlay.refresh()
        }
    }

    func retryDevServer() {
        guard let tab = store.selectedTab, let wait = tab.devServerWait else { return }
        waitForDevServer(tab, url: wait.url, port: wait.port)
    }

    func cancelDevServerWait(of tab: Tab, unlessShowing url: String? = nil) {
        guard let wait = tab.devServerWait, wait.url != url else { return }
        wait.cancel()
        tab.devServerWait = nil
        crashOverlay.refresh()
    }
}
