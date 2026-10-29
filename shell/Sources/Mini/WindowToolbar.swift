import AppKit

@MainActor
final class WindowToolbar: NSObject, NSToolbarDelegate {
    private unowned let commands: ShellController
    let toolbar = NSToolbar(identifier: "MainToolbar")

    private static let sidebarToggle = NSToolbarItem.Identifier("SidebarToggle")
    private static let back = NSToolbarItem.Identifier("Back")
    private static let forward = NSToolbarItem.Identifier("Forward")

    init(commands: ShellController) {
        self.commands = commands
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
    }

    func setItemsHidden(_ hidden: Bool) {
        for item in toolbar.items where [Self.sidebarToggle, Self.back, Self.forward].contains(item.itemIdentifier) {
            item.isHidden = hidden
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebarToggle, .flexibleSpace, Self.back, Self.forward, .sidebarTrackingSeparator]
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
        case Self.sidebarToggle:
            return item(itemIdentifier, "Hide Sidebar", "sidebar.left", #selector(ShellController.toggleTabSidebar(_:)))
        case Self.back:
            return historyItem(itemIdentifier, "Back", "chevron.left", #selector(ShellController.goBackInHistory(_:)), forward: false)
        case Self.forward:
            return historyItem(itemIdentifier, "Forward", "chevron.right", #selector(ShellController.goForwardInHistory(_:)), forward: true)
        default:
            return nil
        }
    }

    private func historyItem(_ identifier: NSToolbarItem.Identifier, _ label: String, _ symbolName: String, _ action: Selector, forward: Bool) -> NSToolbarItem {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) else {
            preconditionFailure("Missing SF Symbol \(symbolName)")
        }
        let button = HistoryButton(image: image, target: commands, action: action)
        Self.style(button, label)
        button.menuProvider = { [unowned commands] in commands.historyMenu(forward: forward) }
        let toolbarItem = HistoryToolbarItem(itemIdentifier: identifier)
        toolbarItem.label = label
        toolbarItem.view = button
        toolbarItem.validation = { [unowned commands] in
            forward ? commands.selectedTabCanGoForward : commands.selectedTabCanGoBack
        }
        return toolbarItem
    }

    private func item(_ identifier: NSToolbarItem.Identifier, _ label: String, _ symbolName: String, _ action: Selector) -> NSToolbarItem {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) else {
            preconditionFailure("Missing SF Symbol \(symbolName)")
        }
        let button = HoverHighlightButton(image: image, target: commands, action: action)
        button.feedback = .toggle
        Self.style(button, label)
        let toolbarItem = NSToolbarItem(itemIdentifier: identifier)
        toolbarItem.label = label
        toolbarItem.view = button
        return toolbarItem
    }

    static func style(_ button: HoverHighlightButton, _ label: String) {
        guard let image = button.image else { preconditionFailure("Toolbar button without a symbol") }
        button.isBordered = false
        button.tooltip = label
        button.title = ""
        button.showSymbol(image, pointSize: 15)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: WindowToolbar.buttonSize.width),
            button.heightAnchor.constraint(equalToConstant: WindowToolbar.buttonSize.height),
        ])
    }

    static let buttonSize = NSSize(width: 32, height: 28)
}
