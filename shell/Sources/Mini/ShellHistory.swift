import AppKit

extension ShellController: NSMenuDelegate {
    private static let recentHistoryTag = 7_701
    private static let recentHistoryCount = 15

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.items.contains(where: { $0.tag == MainMenu.undoItemTag }) {
            updateUndoMenuItems(in: menu)
            return
        }
        for item in menu.items where item.tag == Self.recentHistoryTag {
            menu.removeItem(item)
        }
        guard let firstSeparator = menu.items.firstIndex(where: \.isSeparatorItem) else { return }
        let entries = history.store(forSpace: currentSpace.id).recent(limit: Self.recentHistoryCount)
        var index = firstSeparator + 1
        for entry in entries {
            let item = NSMenuItem(title: Self.menuTitle(entry.displayTitle), action: #selector(openHistoryEntry(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Self.recentHistoryTag
            item.representedObject = entry.url
            item.toolTip = entry.url
            item.image = Self.menuImage(faviconCache.image(forPageAt: entry.url))
            menu.insertItem(item, at: index)
            index += 1
        }
        if !entries.isEmpty {
            let separator = NSMenuItem.separator()
            separator.tag = Self.recentHistoryTag
            menu.insertItem(separator, at: index)
        }
    }

    @objc func openHistoryEntry(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        showWindow()
        open(url, from: .editCurrent)
    }

    @objc func showAllHistory(_ sender: Any?) {
        let controller = historyWindow ?? HistoryWindowController(shell: self)
        historyWindow = controller
        controller.reload()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    @objc func clearHistory(_ sender: Any?) {
        let space = currentSpace
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear history for \u{201C}\(space.name)\u{201D}?"
        alert.informativeText = "Every page visited in this space is removed from history. Open tabs stay open."
        alert.addButton(withTitle: "Clear History").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        let parent = historyWindow?.window?.isKeyWindow == true ? historyWindow?.window ?? window : window
        alert.beginSheetModal(for: parent) { [weak self, weak space] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn, let self, let space, self.spaces.contains(where: { $0 === space }) else { return }
                self.history.store(forSpace: space.id).deleteAll()
                self.historyWindow?.reload()
            }
        }
    }

    func deleteHistoryEntry(_ entry: HistoryEntry) {
        history.store(forSpace: currentSpace.id).delete(url: entry.url)
        historyWindow?.reload()
    }

    func openFromHistoryWindow(_ entry: HistoryEntry) {
        showWindow()
        open(entry.url, from: .newTab)
    }

    var isHistoryWindowKey: Bool {
        guard let historyWindow = historyWindow?.window else { return false }
        return NSApp.keyWindow === historyWindow
    }

    private static func menuTitle(_ title: String) -> String {
        title.count > 60 ? String(title.prefix(60)) + "\u{2026}" : title
    }

    private static func menuImage(_ favicon: NSImage?) -> NSImage {
        guard let source = favicon ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil) else {
            preconditionFailure("Missing SF Symbol globe")
        }
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
    }
}
