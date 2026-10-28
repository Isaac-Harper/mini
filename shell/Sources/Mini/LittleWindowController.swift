import AppKit
import CMiniCore

@MainActor
final class LittleWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSToolbarItemValidation, NSTextFieldDelegate {
    let tab: Tab
    let space: Space
    private unowned let shell: ShellController
    private let toolbar = NSToolbar(identifier: "LittleWindowToolbar")
    private let addressField = NSTextField()
    private var isPromoting = false

    private static let size = NSSize(width: 960, height: 680)
    private static let back = NSToolbarItem.Identifier("LittleBack")
    private static let forward = NSToolbarItem.Identifier("LittleForward")
    private static let address = NSToolbarItem.Identifier("LittleAddress")
    private static let openInMini = NSToolbarItem.Identifier("LittleOpenInMini")

    init(tab: Tab, space: Space, shell: ShellController, cascadeIndex: Int) {
        self.tab = tab
        self.space = space
        self.shell = shell
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unifiedCompact
        window.minSize = NSSize(width: 420, height: 300)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [Self.address]
        window.toolbar = toolbar
        buildAddressField()
        buildContent(in: window)
        window.setFrame(Self.frame(cascadeIndex: cascadeIndex), display: false)
        updateAddress()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func frame(cascadeIndex: Int) -> NSRect {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            preconditionFailure("No screen for the little window")
        }
        let visible = screen.visibleFrame
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let offset = CGFloat(cascadeIndex % 8) * 24
        return NSRect(
            x: visible.midX - width / 2 + offset,
            y: visible.midY - height / 2 - offset,
            width: width,
            height: height
        ).integral
    }

    private func buildAddressField() {
        addressField.isBordered = false
        addressField.isBezeled = false
        addressField.drawsBackground = false
        addressField.focusRingType = .none
        addressField.isEditable = false
        addressField.isSelectable = false
        addressField.alignment = .center
        addressField.font = .systemFont(ofSize: 13, weight: .medium)
        addressField.textColor = .secondaryLabelColor
        addressField.lineBreakMode = .byTruncatingMiddle
        addressField.cell?.usesSingleLineMode = true
        addressField.cell?.isScrollable = true
        addressField.delegate = self
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.widthAnchor.constraint(equalToConstant: 360).isActive = true
    }

    private func buildContent(in window: NSWindow) {
        let container = NSView()
        let hostView = tab.hostView
        hostView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hostView)
        window.contentView = container
        guard let contentLayoutGuide = window.contentLayoutGuide as? NSLayoutGuide else {
            preconditionFailure("Little window has no content layout guide")
        }
        NSLayoutConstraint.activate([
            hostView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
        ])
        container.layoutSubtreeIfNeeded()
    }

    func detachHostViewForPromotion() {
        isPromoting = true
        let hostView = tab.hostView
        hostView.removeFromSuperview()
        hostView.translatesAutoresizingMaskIntoConstraints = true
        close()
    }

    func updateAddress() {
        guard addressField.currentEditor() == nil else { return }
        addressField.stringValue = URLInput.host(of: tab.url) ?? tab.url
        window?.title = tab.displayTitle
        toolbar.validateVisibleItems()
    }

    func editAddress() {
        guard let window else { return }
        addressField.isEditable = true
        addressField.isSelectable = true
        addressField.alignment = .left
        addressField.textColor = .labelColor
        addressField.stringValue = tab.url
        window.makeFirstResponder(addressField)
        addressField.currentEditor()?.selectAll(nil)
    }

    private func endEditingAddress() {
        addressField.isEditable = false
        addressField.isSelectable = false
        addressField.alignment = .center
        addressField.textColor = .secondaryLabelColor
        focusWebContent()
        updateAddress()
    }

    func focusWebContent() {
        guard let window, let webView = tab.hostView.webView else { return }
        window.makeFirstResponder(webView)
        if tab.hasBrowser {
            mini_browser_set_focus(tab.id, true)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            let input = addressField.stringValue
            window?.makeFirstResponder(nil)
            endEditingAddress()
            if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                shell.navigateLittleWindow(self, to: URLInput.interpret(input).url)
            }
        case #selector(NSResponder.cancelOperation(_:)):
            window?.makeFirstResponder(nil)
            endEditingAddress()
        default:
            return false
        }
        return true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        if addressField.isEditable {
            endEditingAddress()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if addressField.currentEditor() == nil {
            focusWebContent()
        }
    }

    func windowWillClose(_ notification: Notification) {
        shell.littleWindowWillClose(self, promoting: isPromoting)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.back, Self.forward, .flexibleSpace, Self.address, .flexibleSpace, Self.openInMini]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.back:
            return button(itemIdentifier, "Back", "chevron.left", #selector(goBack(_:)))
        case Self.forward:
            return button(itemIdentifier, "Forward", "chevron.right", #selector(goForward(_:)))
        case Self.openInMini:
            return button(itemIdentifier, "Open in Mini", "macwindow.badge.plus", #selector(openInMini(_:)))
        case Self.address:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = addressField
            item.label = "Address"
            item.isBordered = false
            return item
        default:
            return nil
        }
    }

    private func button(_ identifier: NSToolbarItem.Identifier, _ label: String, _ symbolName: String, _ action: Selector) -> NSToolbarItem {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) else {
            preconditionFailure("Missing SF Symbol \(symbolName)")
        }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = label
        item.image = image
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.action {
        case #selector(goBack(_:)):
            return tab.hasBrowser && tab.canGoBack
        case #selector(goForward(_:)):
            return tab.hasBrowser && tab.canGoForward
        default:
            return true
        }
    }

    @objc private func goBack(_ sender: Any?) {
        if tab.hasBrowser { mini_browser_go_back(tab.id) }
    }

    @objc private func goForward(_ sender: Any?) {
        if tab.hasBrowser { mini_browser_go_forward(tab.id) }
    }

    @objc private func openInMini(_ sender: Any?) {
        shell.promoteLittleWindow(self)
    }
}
