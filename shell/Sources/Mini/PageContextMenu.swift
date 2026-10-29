import AppKit
import CMiniCore
import MiniRules

struct PageContextRequest: Sendable {
    let flags: UInt32
    let editCapabilities: UInt32
    let location: NSPoint
    let linkURL: String
    let imageURL: String
    let selectionText: String
    let misspelledWord: String
    let suggestions: [String]

    init(_ menu: MiniContextMenu) {
        flags = menu.flags
        editCapabilities = menu.edit_capabilities
        location = NSPoint(x: CGFloat(menu.x), y: CGFloat(menu.y))
        linkURL = String(cString: menu.link_url)
        imageURL = String(cString: menu.image_url)
        selectionText = String(cString: menu.selection_text)
        misspelledWord = String(cString: menu.misspelled_word)
        suggestions = (0..<menu.suggestion_count).map { index in
            guard let suggestion = menu.suggestions[index] else { preconditionFailure("Null spelling suggestion") }
            return String(cString: suggestion)
        }
    }

    func has(_ flag: MiniContextMenuFlag) -> Bool { flags & flag.rawValue != 0 }

    func can(_ capability: MiniEditCapability) -> Bool { editCapabilities & capability.rawValue != 0 }
}

@MainActor
final class PageContextMenu: NSObject {
    private unowned let shell: ShellController
    private let tab: Tab
    private let request: PageContextRequest
    private var actions: [() -> Void] = []

    init(shell: ShellController, tab: Tab, request: PageContextRequest) {
        self.shell = shell
        self.tab = tab
        self.request = request
    }

    func show() {
        guard tab.hasBrowser, let webView = tab.hostView.webView, webView.window != nil else { return }
        let menu = makeMenu()
        let location = NSPoint(x: request.location.x, y: webView.isFlipped ? request.location.y : webView.bounds.height - request.location.y)
        menu.popUp(positioning: nil, at: location, in: webView)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let isMainWindowTab = shell.space(containing: tab.id) != nil
        if request.has(MINI_CONTEXT_EDITABLE), !request.misspelledWord.isEmpty {
            if request.suggestions.isEmpty {
                add(to: menu, "No Guesses Found", enabled: false) {}
            }
            for suggestion in request.suggestions {
                add(to: menu, suggestion) { [tab] in suggestion.withCString { mini_browser_replace_misspelling(tab.id, $0) } }
            }
            add(to: menu, "Learn Spelling", symbol: "text.book.closed") { [tab, request] in request.misspelledWord.withCString { mini_browser_add_word_to_dictionary(tab.id, $0) } }
            menu.addItem(.separator())
        }
        if request.has(MINI_CONTEXT_LINK), !request.linkURL.isEmpty {
            let url = request.linkURL
            add(to: menu, "Open Link in New Tab", symbol: "plus.square.on.square") { [shell, tab] in shell.openLinkInNewTab(url, from: tab) }
            add(to: menu, "Open Link in Split View", symbol: "rectangle.split.2x1", enabled: isMainWindowTab) { [shell, tab] in shell.openLinkInSplitView(url, from: tab) }
            if PlayerSlot.isYouTubeVideo(url), tab !== shell.store.playerTab {
                add(to: menu, "Play in Player", symbol: "play.rectangle") { [shell] in shell.playInPlayer(url) }
            }
            add(to: menu, "Copy Link", symbol: "link") { Self.copyToPasteboard(url) }
            menu.addItem(.separator())
        }
        if request.has(MINI_CONTEXT_IMAGE), !request.imageURL.isEmpty {
            let url = request.imageURL
            add(to: menu, "Open Image in New Tab", symbol: "photo") { [shell, tab] in shell.openLinkInNewTab(url, from: tab) }
            add(to: menu, "Copy Image", symbol: "doc.on.doc") { [tab] in url.withCString { mini_browser_copy_image(tab.id, $0) } }
            add(to: menu, "Save Image As\u{2026}", symbol: "square.and.arrow.down") { [shell, tab] in shell.saveImage(at: url, from: tab) }
            menu.addItem(.separator())
        }
        if request.has(MINI_CONTEXT_EDITABLE) {
            addEdit(to: menu, "Cut", symbol: "scissors", MINI_EDIT_CUT, MINI_EDIT_CAN_CUT)
            addEdit(to: menu, "Copy", symbol: "doc.on.doc", MINI_EDIT_COPY, MINI_EDIT_CAN_COPY)
            addEdit(to: menu, "Paste", symbol: "doc.on.clipboard", MINI_EDIT_PASTE, MINI_EDIT_CAN_PASTE)
            addEdit(to: menu, "Select All", symbol: "checkmark.circle", MINI_EDIT_SELECT_ALL, MINI_EDIT_CAN_SELECT_ALL)
            menu.addItem(.separator())
        }
        let selection = request.selectionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if request.has(MINI_CONTEXT_SELECTION), !request.has(MINI_CONTEXT_LINK), !selection.isEmpty {
            if !request.has(MINI_CONTEXT_EDITABLE) {
                addEdit(to: menu, "Copy", symbol: "doc.on.doc", MINI_EDIT_COPY, MINI_EDIT_CAN_COPY)
            }
            add(to: menu, "Look Up \u{201C}\(Self.abbreviated(selection))\u{201D}", symbol: "character.book.closed") { [weak self] in self?.lookUp(selection) }
            add(to: menu, "Search for \u{201C}\(Self.abbreviated(selection))\u{201D}", symbol: "magnifyingglass") { [shell, tab] in
                shell.openLinkInNewTab(URLInput.Interpretation.search(selection).url, from: tab)
            }
            menu.addItem(.separator())
        }
        if !request.has(MINI_CONTEXT_LINK), !request.has(MINI_CONTEXT_IMAGE), !request.has(MINI_CONTEXT_SELECTION), !request.has(MINI_CONTEXT_EDITABLE) {
            add(to: menu, "Back", symbol: "chevron.left", enabled: tab.canGoBack) { [tab] in mini_browser_go_back(tab.id) }
            add(to: menu, "Forward", symbol: "chevron.right", enabled: tab.canGoForward) { [tab] in mini_browser_go_forward(tab.id) }
            add(to: menu, "Reload", symbol: "arrow.clockwise") { [shell, tab] in shell.reloadByUser(tab) }
            add(to: menu, "View Source", symbol: "chevron.left.forwardslash.chevron.right") { [tab] in SourceWindowController.show(sourceOf: tab) }
            menu.addItem(.separator())
        }
        let point = request.location
        add(to: menu, "Inspect Element", symbol: "hammer") { [tab] in mini_browser_inspect_element(tab.id, Int32(point.x), Int32(point.y)) }
        return menu
    }

    private func addEdit(to menu: NSMenu, _ title: String, symbol: String, _ command: MiniEditCommand, _ capability: MiniEditCapability) {
        add(to: menu, title, symbol: symbol, enabled: request.can(capability)) { [tab] in mini_browser_edit(tab.id, Int32(command.rawValue)) }
    }

    private func add(to menu: NSMenu, _ title: String, symbol: String? = nil, enabled: Bool = true, action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: #selector(performItem(_:)), keyEquivalent: "")
        item.image = symbol.map(MainMenu.symbolImage)
        item.target = self
        item.tag = actions.count
        item.isEnabled = enabled
        actions.append(action)
        menu.addItem(item)
    }

    @objc private func performItem(_ sender: NSMenuItem) {
        guard tab.hasBrowser else { return }
        actions[sender.tag]()
    }

    private func lookUp(_ text: String) {
        guard let webView = tab.hostView.webView else { return }
        let point = NSPoint(x: request.location.x, y: webView.isFlipped ? request.location.y : webView.bounds.height - request.location.y)
        webView.showDefinition(for: NSAttributedString(string: text), at: point)
    }

    private static func abbreviated(_ text: String) -> String {
        let singleLine = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return singleLine.count > 30 ? String(singleLine.prefix(30)) + "\u{2026}" : singleLine
    }

    private static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension ShellController {
    func contextMenuRequested(_ identifier: MiniTabId, request: PageContextRequest) {
        guard let tab = liveTab(identifier) else { return }
        let menu = PageContextMenu(shell: self, tab: tab, request: request)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { menu.show() }
        }
    }

    func imageCopied(_ identifier: MiniTabId, pngData: Data) {
        guard !pngData.isEmpty, let image = NSImage(data: pngData) else {
            toast.show("Could Not Copy Image")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        toast.show("Copied")
    }

    func openLinkInNewTab(_ url: String, from tab: Tab) {
        if let littleWindow = littleWindow(containing: tab.id) {
            openTabRequested(littleWindow.tab.id, url: url, foreground: false)
            return
        }
        guard let tabStore = space(containing: tab.id)?.store else { return }
        tabStore.newTab(url: url, parent: tab.isPinned ? nil : tab, after: nil)
    }

    func openLinkInSplitView(_ url: String, from tab: Tab) {
        guard let tabStore = space(containing: tab.id)?.store, tabStore === store else { return }
        performUndoable("Split View") {
            let opened = store.newTab(url: url, parent: tab.isPinned ? nil : tab)
            if tab.isPinned {
                store.select(opened)
                return
            }
            store.makeSplit(leading: tab, trailing: opened)
            store.select(tab)
        }
    }

    func saveImage(at url: String, from tab: Tab) {
        let panel = NSSavePanel()
        let suggestedName = URL(string: url)?.lastPathComponent ?? ""
        panel.nameFieldStringValue = suggestedName.isEmpty || suggestedName == "/" ? "image" : suggestedName
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        let parentWindow = littleWindow(containing: tab.id)?.window ?? window
        panel.beginSheetModal(for: parentWindow) { [weak tab] response in
            MainActor.assumeIsolated {
                guard response == .OK, let tab, tab.hasBrowser, let destination = panel.url else { return }
                url.withCString { url in destination.path.withCString { mini_browser_save_url(tab.id, url, $0) } }
            }
        }
    }
}
