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
            return item(itemIdentifier, "Back", "chevron.left", #selector(ShellController.goBackInHistory(_:)))
        case Self.forward:
            return item(itemIdentifier, "Forward", "chevron.right", #selector(ShellController.goForwardInHistory(_:)))
        default:
            return nil
        }
    }

    private func item(_ identifier: NSToolbarItem.Identifier, _ label: String, _ symbolName: String, _ action: Selector) -> NSToolbarItem {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) else {
            preconditionFailure("Missing SF Symbol \(symbolName)")
        }
        let toolbarItem = NSToolbarItem(itemIdentifier: identifier)
        toolbarItem.label = label
        toolbarItem.toolTip = label
        toolbarItem.image = image
        toolbarItem.isBordered = true
        toolbarItem.target = commands
        toolbarItem.action = action
        return toolbarItem
    }
}
