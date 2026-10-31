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
        let text = ReloadTemperatures.label(milliseconds: milliseconds, temperature: tab.reloadTemperature)
        showReloadLabel(text, spoken: "Reloaded in \(text)", holding: ReloadTemperatures.hold(for: tab.reloadTemperature), of: tab)
    }

    func showRefreshDuration(_ milliseconds: Double, of tab: Tab) {
        showReloadLabel(DevBuildStatus.refreshLabel(milliseconds: milliseconds),
                        spoken: "Refreshed in \(DurationText.milliseconds(milliseconds))", holding: ReloadTemperatures.labeledHold, of: tab)
    }

    private func showReloadLabel(_ text: String, spoken: String, holding hold: TimeInterval, of tab: Tab) {
        tab.reloadDurationGeneration += 1
        let generation = tab.reloadDurationGeneration
        tab.reloadDurationSpokenText = spoken
        tab.reloadDurationText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak tab] in
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
