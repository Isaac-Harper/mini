import AppKit
import CMiniCore
import MiniRules
import Observation

extension ShellController {
    func reloadByUser(_ tab: Tab, ignoringCache: Bool = false) {
        guard tab.hasBrowser else { return }
        let reload = ReloadTemperatures.reload(ignoringCache: ignoringCache, url: tab.url, at: Date(), after: tab.lastColdReload)
        tab.reloadTemperature = reload.temperature
        tab.lastColdReload = reload.remembered
        tab.awaitsReloadTiming = true
        if ignoringCache {
            mini_browser_reload_ignoring_cache(tab.id)
        } else {
            mini_browser_reload(tab.id)
        }
    }

    func showReloadDuration(_ milliseconds: Double, of tab: Tab) {
        tab.reloadDurationGeneration += 1
        let generation = tab.reloadDurationGeneration
        tab.reloadDurationText = ReloadTemperatures.label(milliseconds: milliseconds, temperature: tab.reloadTemperature)
        DispatchQueue.main.asyncAfter(deadline: .now() + ReloadTemperatures.hold(for: tab.reloadTemperature)) { [weak tab] in
            MainActor.assumeIsolated {
                guard let tab, tab.reloadDurationGeneration == generation else { return }
                tab.reloadDurationText = nil
            }
        }
    }
}

@MainActor
@Observable
final class ReloadOptionKey {
    private(set) var isHeld = false
    @ObservationIgnored private var monitor: Any?

    func hoverChanged(_ inside: Bool) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        guard inside else {
            isHeld = false
            return
        }
        isHeld = NSEvent.modifierFlags.contains(.option)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let held = event.modifierFlags.contains(.option)
            MainActor.assumeIsolated { self?.isHeld = held }
            return event
        }
    }
}
