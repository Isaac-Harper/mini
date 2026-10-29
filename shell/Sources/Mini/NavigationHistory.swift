import AppKit
import CMiniCore

struct NavigationEntry {
    let index: Int
    let isCurrent: Bool
    let url: String
    let title: String
}

private final class NavigationEntryCollector {
    var entries: [NavigationEntry] = []
}

private func collectNavigationEntry(
    context: UnsafeMutableRawPointer?, index: Int32, isCurrent: Bool, url: UnsafePointer<CChar>?, title: UnsafePointer<CChar>?
) {
    guard let context, let url, let title else { preconditionFailure("Navigation entry visitor got a null argument") }
    let collector = Unmanaged<NavigationEntryCollector>.fromOpaque(context).takeUnretainedValue()
    collector.entries.append(NavigationEntry(index: Int(index), isCurrent: isCurrent, url: String(cString: url), title: String(cString: title)))
}

@MainActor
enum NavigationHistory {
    static func entries(of tab: Tab) -> [NavigationEntry] {
        guard tab.hasBrowser else { return [] }
        let collector = NavigationEntryCollector()
        withExtendedLifetime(collector) {
            mini_browser_visit_navigation_entries(tab.id, collectNavigationEntry, Unmanaged.passUnretained(collector).toOpaque())
        }
        return collector.entries
    }

    static func menu(for tab: Tab, forward: Bool, faviconCache: FaviconCache, target: AnyObject, action: Selector) -> NSMenu {
        let entries = entries(of: tab)
        let menu = NSMenu()
        guard let current = entries.first(where: \.isCurrent) else { return menu }
        let candidates = forward ? Array(entries.drop { $0.index <= current.index }) : entries.filter { $0.index < current.index }.reversed()
        for entry in candidates {
            let title = entry.title.isEmpty ? entry.url : entry.title
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = HistoryJump(tab: tab, offset: entry.index - current.index)
            item.image = menuImage(faviconCache.image(forPageAt: entry.url))
            item.toolTip = entry.url
            menu.addItem(item)
        }
        return menu
    }

    private static func menuImage(_ favicon: NSImage?) -> NSImage {
        let source = favicon ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        guard let source else { preconditionFailure("Missing SF Symbol globe") }
        let size = NSSize(width: 16, height: 16)
        return NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
    }
}

@MainActor
final class HistoryJump: NSObject {
    weak var tab: Tab?
    let offset: Int32

    init(tab: Tab, offset: Int) {
        self.tab = tab
        self.offset = Int32(offset)
    }
}

final class HistoryButton: HoverHighlightButton {
    var menuProvider: (() -> NSMenu)?

    private static let longPressDelay: TimeInterval = 0.4

    override func rightMouseDown(with event: NSEvent) {
        showHistoryMenu()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window else { return }
        highlight(true)
        let mouseUp = window.nextEvent(matching: .leftMouseUp, until: Date(timeIntervalSinceNow: Self.longPressDelay), inMode: .eventTracking, dequeue: true)
        highlight(false)
        guard let mouseUp else {
            showHistoryMenu()
            return
        }
        if bounds.contains(convert(mouseUp.locationInWindow, from: nil)) {
            sendAction(action, to: target)
        }
    }

    func showHistoryMenu() {
        guard let menu = menuProvider?(), !menu.items.isEmpty else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: isFlipped ? bounds.height + 4 : -4), in: self)
    }
}

final class HistoryToolbarItem: NSToolbarItem {
    var validation: (() -> Bool)?

    override func validate() {
        let enabled = validation?() ?? true
        isEnabled = enabled
        (view as? NSControl)?.isEnabled = enabled
    }
}
