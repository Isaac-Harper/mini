import AppKit

@MainActor
enum MainMenu {
    static func make(commands: ShellController) -> NSMenu {
        let mainMenu = NSMenu()
        for submenu in [
            applicationMenu(commands),
            fileMenu(commands),
            editMenu(commands),
            viewMenu(commands),
            historyMenu(commands),
            tabsMenu(commands),
            spacesMenu(commands),
            windowMenu(),
        ] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }

    private static func applicationMenu(_ commands: ShellController) -> NSMenu {
        let menu = NSMenu(title: "Mini")
        menu.addItem(withTitle: "About Mini", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(item("Set as Default Browser", #selector(ShellController.setAsDefaultBrowser(_:)), "", target: commands))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Mini", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Mini", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu(_ commands: ShellController) -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Tab", #selector(ShellController.newTab(_:)), "t", target: commands))
        menu.addItem(item("New Child Tab", #selector(ShellController.newChildTab(_:)), "t", [.command, .option], target: commands))
        menu.addItem(item("Reopen Closed Tab", #selector(ShellController.reopenClosedTab(_:)), "t", [.command, .shift], target: commands))
        menu.addItem(item("Open Location", #selector(ShellController.openLocation(_:)), "l", target: commands))
        menu.addItem(item("Open in Mini", #selector(ShellController.openLittleWindowInMini(_:)), "o", target: commands))
        menu.addItem(.separator())
        menu.addItem(item("Print\u{2026}", #selector(ShellController.printPage(_:)), "p", target: commands))
        menu.addItem(.separator())
        menu.addItem(item("Close Tab", #selector(ShellController.closeTab(_:)), "w", target: commands))
        return menu
    }

    private static func editMenu(_ commands: ShellController) -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]))
        menu.addItem(item("Delete", #selector(NSText.delete(_:)), ""))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(item("Copy URL", #selector(ShellController.copyTabAddress(_:)), "c", [.command, .shift], target: commands))
        menu.addItem(.separator())
        menu.addItem(item("Find", #selector(ShellController.showFindBar(_:)), "f", target: commands))
        menu.addItem(item("Find Next", #selector(ShellController.findNextMatch(_:)), "g", target: commands))
        menu.addItem(item("Find Previous", #selector(ShellController.findPreviousMatch(_:)), "g", [.command, .shift], target: commands))
        menu.addItem(.separator())
        menu.addItem(item("Fill Password", #selector(ShellController.fillPassword(_:)), "\\", target: commands))
        return menu
    }

    private static func viewMenu(_ commands: ShellController) -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Hide Sidebar", #selector(ShellController.toggleTabSidebar(_:)), "s", [.command, .control], target: commands))
        menu.addItem(item("Split View", #selector(ShellController.toggleSplitViewCommand(_:)), "\\", [.command, .control], target: commands))
        menu.addItem(.separator())
        menu.addItem(item("Reload Page", #selector(ShellController.reloadPage(_:)), "r", target: commands))
        menu.addItem(item("Stop", #selector(ShellController.stopLoading(_:)), ".", target: commands))
        menu.addItem(.separator())
        menu.addItem(item("Zoom In", #selector(ShellController.zoomInPage(_:)), "=", target: commands))
        menu.addItem(hiddenShortcut(item("Zoom In", #selector(ShellController.zoomInPage(_:)), "+", target: commands)))
        menu.addItem(item("Zoom Out", #selector(ShellController.zoomOutPage(_:)), "-", target: commands))
        menu.addItem(item("Actual Size", #selector(ShellController.actualSizePage(_:)), "0", target: commands))
        menu.addItem(.separator())
        menu.addItem(item("Block Ads on This Site", #selector(ShellController.toggleAdBlockForSite(_:)), "", target: commands))
        menu.addItem(item("Allow Notifications from This Site", #selector(ShellController.toggleNotificationsForSite(_:)), "", target: commands))
        menu.addItem(item("Reset Permissions for This Site", #selector(ShellController.resetPermissionsForSite(_:)), "", target: commands))
        menu.addItem(item("Clear Data for This Site\u{2026}", #selector(ShellController.clearDataForSite(_:)), "", target: commands))
        menu.addItem(.separator())
        menu.addItem(item("Picture in Picture", #selector(ShellController.togglePictureInPicture(_:)), "p", [.command, .option], target: commands))
        menu.addItem(.separator())
        menu.addItem(item("Developer Tools", #selector(ShellController.showDeveloperTools(_:)), "i", [.command, .option], target: commands))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func historyMenu(_ commands: ShellController) -> NSMenu {
        let menu = NSMenu(title: "History")
        menu.addItem(item("Back", #selector(ShellController.goBackInHistory(_:)), "[", target: commands))
        menu.addItem(item("Forward", #selector(ShellController.goForwardInHistory(_:)), "]", target: commands))
        menu.addItem(.separator())
        menu.addItem(item("Show All History", #selector(ShellController.showAllHistory(_:)), "y", target: commands))
        menu.addItem(item("Clear History\u{2026}", #selector(ShellController.clearHistory(_:)), "", target: commands))
        menu.delegate = commands
        return menu
    }

    private static func tabsMenu(_ commands: ShellController) -> NSMenu {
        let menu = NSMenu(title: "Tabs")
        let downArrow = String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!)
        let upArrow = String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!)
        let rightArrow = String(UnicodeScalar(UInt16(NSRightArrowFunctionKey))!)
        let leftArrow = String(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!)
        menu.addItem(item("Next Tab", #selector(ShellController.selectNextTab(_:)), "\t", [.control], target: commands))
        menu.addItem(hiddenShortcut(item("Next Tab", #selector(ShellController.selectNextTab(_:)), downArrow, [.command, .option], target: commands)))
        menu.addItem(item("Previous Tab", #selector(ShellController.selectPreviousTab(_:)), "\t", [.control, .shift], target: commands))
        menu.addItem(hiddenShortcut(item("Previous Tab", #selector(ShellController.selectPreviousTab(_:)), upArrow, [.command, .option], target: commands)))
        menu.addItem(.separator())
        menu.addItem(item("Indent Tab", #selector(ShellController.indentTab(_:)), rightArrow, [.command, .option], target: commands))
        menu.addItem(item("Outdent Tab", #selector(ShellController.outdentTab(_:)), leftArrow, [.command, .option], target: commands))
        menu.addItem(item("Move Tab Up", #selector(ShellController.moveTabUp(_:)), upArrow, [.control, .shift], target: commands))
        menu.addItem(item("Move Tab Down", #selector(ShellController.moveTabDown(_:)), downArrow, [.control, .shift], target: commands))
        menu.addItem(item("Pin Tab", #selector(ShellController.togglePinnedTab(_:)), "p", [.command, .control], target: commands))
        menu.addItem(item("Duplicate Tab", #selector(ShellController.duplicateSelectedTab(_:)), "d", [.command, .shift], target: commands))
        menu.addItem(item("Collapse Group", #selector(ShellController.toggleTabGroup(_:)), "\\", [.command, .option], target: commands))
        menu.addItem(.separator())
        for index in 1...9 {
            let title = index == 9 ? "Select Last Tab" : "Select Tab \(index)"
            let selectItem = item(title, #selector(ShellController.selectTabAtIndex(_:)), "\(index)", target: commands)
            selectItem.tag = index
            menu.addItem(selectItem)
        }
        return menu
    }

    private static func spacesMenu(_ commands: ShellController) -> NSMenu {
        let menu = NSMenu(title: "Space")
        menu.addItem(item("New Space\u{2026}", #selector(ShellController.newSpace(_:)), "", target: commands))
        menu.addItem(item("Rename Space\u{2026}", #selector(ShellController.renameCurrentSpace(_:)), "", target: commands))
        menu.addItem(item("Delete Space\u{2026}", #selector(ShellController.deleteCurrentSpace(_:)), "", target: commands))
        menu.addItem(.separator())
        for index in 1...9 {
            let selectItem = item("Space \(index)", #selector(ShellController.selectSpaceAtIndex(_:)), "\(index)", [.control], target: commands)
            selectItem.tag = index
            selectItem.allowsKeyEquivalentWhenHidden = true
            menu.addItem(selectItem)
        }
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = menu
        return menu
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        _ keyEquivalent: String,
        _ modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = target
        return menuItem
    }

    private static func hiddenShortcut(_ menuItem: NSMenuItem) -> NSMenuItem {
        menuItem.isHidden = true
        menuItem.allowsKeyEquivalentWhenHidden = true
        return menuItem
    }
}
