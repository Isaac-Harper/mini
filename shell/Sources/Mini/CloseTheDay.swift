import AppKit
import CMiniCore
import MiniRules

struct DayFold: Hashable {
    let day: Date
    let foldedAt: Date
}

extension ShellController {
    static let foldSlideDuration: TimeInterval = 0.45

    func closeTheDayIfNeeded(now: Date = Date(), includingSavedSelections: Bool = false) {
        let calendar = Calendar.current
        guard DayClosing.isNewDay(at: now, lastClosedDay: sessionStore.closedDay, calendar: calendar) else { return }
        sessionStore.closedDay = DayClosing.day(containing: now, calendar: calendar)
        scheduleSessionSave()
        guard closesDayAutomatically else { return }
        let savedSelections = includingSavedSelections ? savedSession.spaces.flatMap { $0.contents.tabs.flatMap(Self.selectionDates) } : []
        guard let day = DayClosing.previousActiveDay(before: now, selections: allSpaceTabs.map(\.lastSelectedAt) + savedSelections, calendar: calendar) else { return }
        foldTabs(selectedBefore: DayClosing.start(ofDay: day, calendar: calendar), into: day, now: now, animated: !includingSavedSelections)
    }

    func closeTheDayNow(now: Date = Date()) {
        let day = DayClosing.day(containing: now, calendar: .current)
        if foldTabs(selectedBefore: now, into: day, now: now, animated: true) == 0 {
            toast.show("No Tabs to Fold")
        }
    }

    func observeWakeForClosingTheDay() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeTheDayIfNeeded() }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeTheDayIfNeeded() }
        }
    }

    func restoreFold(_ group: DayFoldGroup) {
        performUndoable("Restore Tabs") { store.unfold(day: group.day) }
    }

    func archiveFold(_ group: DayFoldGroup) {
        archiveTabs(group.roots)
    }

    func foldLabel(for day: Date) -> String {
        DayClosing.label(forDay: day, now: Date(), calendar: .current, locale: .current)
    }

    @discardableResult
    private func foldTabs(selectedBefore cutoff: Date, into day: Date, now: Date, animated: Bool) -> Int {
        let fold = DayFold(day: day, foldedAt: now)
        var foldedInCurrentSpace = 0
        for space in spaces {
            let store = space.store
            let roots = foldableRoots(in: store, selectedBefore: cutoff)
            guard !roots.isEmpty else { continue }
            guard store === self.store else {
                store.fold(roots, into: fold)
                continue
            }
            let slides = animated && window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let wasExpanded = store.expandedFoldDays.contains(day)
            if slides {
                store.setFold(day: day, expanded: true)
            }
            performUndoable("Close the Day") { store.fold(roots, into: fold) }
            foldedInCurrentSpace = roots.reduce(0) { $0 + $1.subtree.count }
            undoToast.show(DayClosing.foldMessage(label: DayClosing.label(forDay: day, now: now, calendar: .current, locale: .current), tabCount: foldedInCurrentSpace))
            if slides, !wasExpanded {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.foldSlideDuration) {
                    MainActor.assumeIsolated { store.setFold(day: day, expanded: false) }
                }
            }
        }
        return foldedInCurrentSpace
    }

    private func foldableRoots(in store: TabStore, selectedBefore cutoff: Date) -> [Tab] {
        let selected = store.selectedTab
        func candidate(_ tab: Tab) -> DayClosing.Candidate<MiniTabId> {
            DayClosing.Candidate(
                identifier: tab.id,
                lastSelectedAt: tab.lastSelectedAt,
                isKept: tab === selected || store.split(containing: tab) != nil || tab.isPlayingAudio || (tab.hasBrowser && mini_browser_has_unsaved_input(tab.id)),
                children: tab.children.map(candidate)
            )
        }
        let identifiers = DayClosing.rootsToFold(store.rootTabs.filter { $0.dayFold == nil }.map(candidate), selectedBefore: cutoff)
        return identifiers.compactMap(store.tab(withIdentifier:))
    }

    private static func selectionDates(_ tab: SavedSpaceContents.SavedTab) -> [Date] {
        (tab.lastSelectedAt.map { [$0] } ?? []) + tab.children.flatMap(selectionDates)
    }
}
