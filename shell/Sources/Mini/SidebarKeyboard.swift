import AppKit
import CMiniCore
import Observation
import SwiftUI

@MainActor
@Observable
final class SidebarKeyboardFocus {
    var focusedTabIdentifier: MiniTabId?
}

extension ShellController {
    private var sidebarKeyboardItems: [Tab] {
        store.pinnedTabs + store.visibleTabs.map(\.tab)
    }

    func focusSidebarFromKeyboard() {
        guard windowController.isSidebarVisible, !isOverlayActive else { return }
        let items = sidebarKeyboardItems
        guard !items.isEmpty else { return }
        let start = store.selectedTab.flatMap { selected in items.first { $0 === selected } } ?? items[0]
        guard windowController.focusSidebar() else { return }
        sidebarKeyboard.focusedTabIdentifier = start.id
    }

    func installSidebarTabKeyMonitor() -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.focusesSidebar(for: event) ?? false }
            return consumed ? nil : event
        }
    }

    private func focusesSidebar(for event: NSEvent) -> Bool {
        guard event.keyCode == 48, event.window === window,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              window.firstResponder == nil || window.firstResponder === window else { return false }
        focusSidebarFromKeyboard()
        return sidebarKeyboard.focusedTabIdentifier != nil
    }

    func sidebarResignedKeyboardFocus() {
        sidebarKeyboard.focusedTabIdentifier = nil
    }

    func sidebarKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        let items = sidebarKeyboardItems
        guard let index = items.firstIndex(where: { $0.id == sidebarKeyboard.focusedTabIdentifier }) else {
            if let first = items.first { sidebarKeyboard.focusedTabIdentifier = first.id }
            return true
        }
        let tab = items[index]
        switch event.keyCode {
        case 125:
            moveSidebarFocus(to: min(index + 1, items.count - 1), in: items)
        case 126:
            moveSidebarFocus(to: max(index - 1, 0), in: items)
        case 123:
            if tab.isPinned {
                moveSidebarFocus(to: max(index - 1, 0), in: items)
            } else if !tab.children.isEmpty, !tab.isCollapsed {
                store.toggleCollapse(tab)
            } else if let parent = tab.parent {
                sidebarKeyboard.focusedTabIdentifier = parent.id
            }
        case 124:
            if tab.isPinned {
                moveSidebarFocus(to: min(index + 1, items.count - 1), in: items)
            } else if !tab.children.isEmpty, tab.isCollapsed {
                store.toggleCollapse(tab)
            } else if let child = tab.children.first {
                sidebarKeyboard.focusedTabIdentifier = child.id
            }
        case 36, 76:
            store.select(tab)
            returnFocusToPage()
        case 51, 117:
            let remaining = items.filter { $0 !== tab && !$0.isDescendant(of: tab) }
            let next = items[(index + 1)...].first { !$0.isDescendant(of: tab) } ?? items[..<index].last
            performUndoable("Close Tab") { store.close(tab) }
            let following = next.flatMap { candidate in remaining.contains { $0 === candidate } ? candidate : nil }
            sidebarKeyboard.focusedTabIdentifier = (following ?? sidebarKeyboardItems.first)?.id
            if sidebarKeyboard.focusedTabIdentifier == nil { returnFocusToPage() }
        case 48, 53:
            returnFocusToPage()
        default:
            return false
        }
        return true
    }

    private func moveSidebarFocus(to index: Int, in items: [Tab]) {
        sidebarKeyboard.focusedTabIdentifier = items[index].id
    }

    private func returnFocusToPage() {
        sidebarKeyboard.focusedTabIdentifier = nil
        window.makeFirstResponder(nil)
        focusSelectedWebContent()
    }
}

struct SidebarFocusRing: View {
    let shell: ShellController
    let tab: Tab
    let cornerRadius: CGFloat

    var body: some View {
        if shell.sidebarKeyboard.focusedTabIdentifier == tab.id {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .allowsHitTesting(false)
        }
    }
}
