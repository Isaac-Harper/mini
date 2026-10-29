import CMiniCore
import Foundation
import MiniRules

extension ShellController {
    private static let reloadDurationHold: TimeInterval = 1.5

    func reloadByUser(_ tab: Tab) {
        guard tab.hasBrowser else { return }
        tab.awaitsReloadTiming = true
        mini_browser_reload(tab.id)
    }

    func showReloadDuration(_ milliseconds: Double, of tab: Tab) {
        tab.reloadDurationGeneration += 1
        let generation = tab.reloadDurationGeneration
        tab.reloadDurationText = DurationText.milliseconds(milliseconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reloadDurationHold) { [weak tab] in
            MainActor.assumeIsolated {
                guard let tab, tab.reloadDurationGeneration == generation else { return }
                tab.reloadDurationText = nil
            }
        }
    }
}
