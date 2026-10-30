import AppKit

@MainActor
enum MainMenu {
    static let undoItemTag = 7_801
    static let redoItemTag = 7_802

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
        menu.addItem(item("About Mini", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "", [], symbol: "info.circle"))
        menu.addItem(item("Set as Default Browser", #selector(ShellController.setAsDefaultBrowser(_:)), "", target: commands, symbol: "globe"))
        menu.addItem(.separator())
        menu.addItem(item("Hide Mini", #selector(NSApplication.hide(_:)), "h", symbol: "eye.slash"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], symbol: "eye.slash"))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:)), "", [], symbol: "eye"))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Mini", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func fileMenu(_ commands: ShellController) -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Tab", #selector(ShellController.newTab(_:)), "t", target: commands, symbol: "plus"))
        menu.addItem(item("New Child Tab", #selector(ShellController.newChildTab(_:)), "t", [.command, .option], target: commands, symbol: "arrow.turn.down.right"))
        menu.addItem(item("Reopen Closed Tab", #selector(ShellController.reopenClosedTab(_:)), "t", [.command, .shift], target: commands, symbol: "arrow.uturn.backward"))
        menu.addItem(item("Open Location", #selector(ShellController.openLocation(_:)), "l", target: commands, symbol: "magnifyingglass"))
        menu.addItem(item("Open in Mini", #selector(ShellController.openLittleWindowInMini(_:)), "o", target: commands, symbol: "macwindow"))
        menu.addItem(item("Open in Safari", #selector(ShellController.openInSafari(_:)), "", target: commands, symbol: "safari"))
        menu.addItem(.separator())
        menu.addItem(item("Print\u{2026}", #selector(ShellController.printPage(_:)), "p", target: commands, symbol: "printer"))
        menu.addItem(.separator())
        menu.addItem(item("Close Tab", #selector(ShellController.closeTab(_:)), "w", target: commands))
        return menu
    }

    private static func editMenu(_ commands: ShellController) -> NSMenu {
        let menu = NSMenu(title: "Edit")
        let undoItem = item("Undo", Selector(("undo:")), "z", symbol: "arrow.uturn.backward")
        undoItem.tag = undoItemTag
        menu.addItem(undoItem)
        let redoItem = item("Redo", Selector(("redo:")), "z", [.command, .shift], symbol: "arrow.uturn.forward")
        redoItem.tag = redoItemTag
        menu.addItem(redoItem)
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x", symbol: "scissors"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c", symbol: "doc.on.doc"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v", symbol: "doc.on.clipboard"))
        menu.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift], symbol: "doc.on.clipboard"))
        menu.addItem(item("Delete", #selector(NSText.delete(_:)), ""))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a", symbol: "checkmark.circle"))
        menu.addItem(item("Copy URL", #selector(ShellController.copyTabAddress(_:)), "c", [.command, .shift], target: commands, symbol: "link"))
        menu.addItem(item("Copy as Markdown Link", #selector(ShellController.copyTabMarkdownLink(_:)), "c", [.command, .option], target: commands, symbol: "link"))
        menu.addItem(.separator())
        menu.addItem(item("Find", #selector(ShellController.showFindBar(_:)), "f", target: commands, symbol: "magnifyingglass"))
        menu.addItem(item("Find Next", #selector(ShellController.findNextMatch(_:)), "g", target: commands, symbol: "chevron.down"))
        menu.addItem(item("Find Previous", #selector(ShellController.findPreviousMatch(_:)), "g", [.command, .shift], target: commands, symbol: "chevron.up"))
        menu.addItem(.separator())
        menu.addItem(item("Fill Password", #selector(ShellController.fillPassword(_:)), "\\", target: commands, symbol: "key.fill"))
        menu.delegate = commands
        return menu
    }

    private static func viewMenu(_ commands: ShellController) -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Hide Sidebar", #selector(ShellController.toggleTabSidebar(_:)), "s", [.command, .control], target: commands, symbol: "sidebar.left"))
        menu.addItem(item("Split View", #selector(ShellController.toggleSplitViewCommand(_:)), "\\", [.command, .control], target: commands, symbol: "rectangle.split.2x1"))
        menu.addItem(item("Evening Tint", #selector(ShellController.toggleEveningTint(_:)), "", target: commands, symbol: "moon"))
        menu.addItem(item("Preload on Hover", #selector(ShellController.togglePreloadOnHover(_:)), "", target: commands, symbol: "bolt"))
        menu.addItem(item("Close the Day Automatically", #selector(ShellController.toggleClosingTheDay(_:)), "", target: commands, symbol: "moon.zzz"))
        menu.addItem(.separator())
        menu.addItem(item("Reload Page", #selector(ShellController.reloadPage(_:)), "r", target: commands, symbol: "arrow.clockwise"))
        menu.addItem(item("Stop", #selector(ShellController.stopLoading(_:)), ".", target: commands, symbol: "xmark"))
        menu.addItem(.separator())
        menu.addItem(item("Zoom In", #selector(ShellController.zoomInPage(_:)), "=", target: commands, symbol: "plus.magnifyingglass"))
        menu.addItem(hiddenShortcut(item("Zoom In", #selector(ShellController.zoomInPage(_:)), "+", target: commands, symbol: "plus.magnifyingglass")))
        menu.addItem(item("Zoom Out", #selector(ShellController.zoomOutPage(_:)), "-", target: commands, symbol: "minus.magnifyingglass"))
        menu.addItem(item("Actual Size", #selector(ShellController.actualSizePage(_:)), "0", target: commands, symbol: "1.magnifyingglass"))
        let interfaceSizeItem = NSMenuItem(title: "Interface Size", action: nil, keyEquivalent: "")
        interfaceSizeItem.image = symbolImage("textformat.size")
        let interfaceSizeMenu = NSMenu(title: "Interface Size")
        interfaceSizeMenu.addItem(item("Larger Interface", #selector(ShellController.largerInterface(_:)), "=", [.command, .control], target: commands, symbol: "textformat.size.larger"))
        interfaceSizeMenu.addItem(item("Smaller Interface", #selector(ShellController.smallerInterface(_:)), "-", [.command, .control], target: commands, symbol: "textformat.size.smaller"))
        interfaceSizeMenu.addItem(item("Actual Interface Size", #selector(ShellController.actualInterfaceSize(_:)), "0", [.command, .control], target: commands, symbol: "textformat.size"))
        interfaceSizeItem.submenu = interfaceSizeMenu
        menu.addItem(interfaceSizeItem)
        menu.addItem(.separator())
        menu.addItem(item("Block Ads on This Site", #selector(ShellController.toggleAdBlockForSite(_:)), "", target: commands, symbol: "hand.raised"))
        menu.addItem(item("Allow Notifications from This Site", #selector(ShellController.toggleNotificationsForSite(_:)), "", target: commands, symbol: "bell"))
        menu.addItem(item("Reset Permissions for This Site", #selector(ShellController.resetPermissionsForSite(_:)), "", target: commands))
        menu.addItem(item("Clear Data for This Site\u{2026}", #selector(ShellController.clearDataForSite(_:)), "", target: commands))
        menu.addItem(.separator())
        menu.addItem(item("Picture in Picture", #selector(ShellController.togglePictureInPicture(_:)), "p", [.command, .option], target: commands, symbol: "pip"))
        menu.addItem(.separator())
        menu.addItem(item("Switch to Production", #selector(ShellController.switchEnvironment(_:)), "P", [.command], target: commands, symbol: "arrow.left.arrow.right"))
        menu.addItem(item("Developer Tools", #selector(ShellController.showDeveloperTools(_:)), "i", [.command, .option], target: commands, symbol: "hammer"))
        menu.addItem(item("View Source", #selector(ShellController.viewSource(_:)), "u", [.command, .option], target: commands, symbol: "chevron.left.forwardslash.chevron.right"))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control], symbol: "arrow.up.left.and.arrow.down.right"))
        return menu
    }

    private static func historyMenu(_ commands: ShellController) -> NSMenu {
        let menu = NSMenu(title: "History")
        menu.addItem(item("Back", #selector(ShellController.goBackInHistory(_:)), "[", target: commands, symbol: "chevron.left"))
        menu.addItem(item("Forward", #selector(ShellController.goForwardInHistory(_:)), "]", target: commands, symbol: "chevron.right"))
        menu.addItem(.separator())
        menu.addItem(item("Show All History", #selector(ShellController.showAllHistory(_:)), "y", target: commands, symbol: "clock"))
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
        menu.addItem(item("Next Tab", #selector(ShellController.selectNextTab(_:)), "\t", [.control], target: commands, symbol: "arrow.down"))
        menu.addItem(hiddenShortcut(item("Next Tab", #selector(ShellController.selectNextTab(_:)), downArrow, [.command, .option], target: commands, symbol: "arrow.down")))
        menu.addItem(item("Previous Tab", #selector(ShellController.selectPreviousTab(_:)), "\t", [.control, .shift], target: commands, symbol: "arrow.up"))
        menu.addItem(hiddenShortcut(item("Previous Tab", #selector(ShellController.selectPreviousTab(_:)), upArrow, [.command, .option], target: commands, symbol: "arrow.up")))
        menu.addItem(.separator())
        menu.addItem(item("Indent Tab", #selector(ShellController.indentTab(_:)), rightArrow, [.command, .option], target: commands, symbol: "increase.indent"))
        menu.addItem(item("Outdent Tab", #selector(ShellController.outdentTab(_:)), leftArrow, [.command, .option], target: commands, symbol: "decrease.indent"))
        menu.addItem(item("Move Tab Up", #selector(ShellController.moveTabUp(_:)), upArrow, [.control, .shift], target: commands, symbol: "arrow.up.square"))
        menu.addItem(item("Move Tab Down", #selector(ShellController.moveTabDown(_:)), downArrow, [.control, .shift], target: commands, symbol: "arrow.down.square"))
        menu.addItem(item("Pin Tab", #selector(ShellController.togglePinnedTab(_:)), "p", [.command, .control], target: commands, symbol: "pin"))
        menu.addItem(item("Make Player Tab", #selector(ShellController.togglePlayerTab(_:)), "", target: commands, symbol: "play.rectangle"))
        menu.addItem(item("Show Player", #selector(ShellController.showPlayerSlot(_:)), "", target: commands, symbol: "play.rectangle.on.rectangle"))
        menu.addItem(item("Save Tab", #selector(ShellController.toggleSavedTab(_:)), "d", target: commands, symbol: "bookmark"))
        menu.addItem(item("Duplicate Tab", #selector(ShellController.duplicateSelectedTab(_:)), "d", [.command, .shift], target: commands, symbol: "plus.square.on.square"))
        menu.addItem(item("Archive Tab", #selector(ShellController.archiveSelectedTabs(_:)), "", target: commands))
        menu.addItem(item("Collapse Group", #selector(ShellController.toggleTabGroup(_:)), "\\", [.command, .option], target: commands, symbol: "rectangle.compress.vertical"))
        menu.addItem(item("Close the Day Now", #selector(ShellController.closeTheDayNowCommand(_:)), "", target: commands, symbol: "moon.zzz"))
        menu.addItem(.separator())
        for index in 1...9 {
            let title = index == 9 ? "Select Last Tab" : "Select Tab \(index)"
            let selectItem = item(title, #selector(ShellController.selectTabAtIndex(_:)), "\(index)", target: commands,
                                  symbol: index == 9 ? "arrow.down.to.line" : "\(index).square")
            selectItem.tag = index
            menu.addItem(selectItem)
        }
        return menu
    }

    private static func spacesMenu(_ commands: ShellController) -> NSMenu {
        let menu = NSMenu(title: "Space")
        menu.addItem(item("New Space\u{2026}", #selector(ShellController.newSpace(_:)), "", target: commands, symbol: "plus"))
        menu.addItem(item("Rename Space\u{2026}", #selector(ShellController.renameCurrentSpace(_:)), "", target: commands, symbol: "pencil"))
        menu.addItem(item("Delete Space\u{2026}", #selector(ShellController.deleteCurrentSpace(_:)), "", target: commands))
        let colorItem = NSMenuItem(title: "Space Color", action: nil, keyEquivalent: "")
        colorItem.image = symbolImage("paintpalette")
        let colorMenu = NSMenu(title: "Space Color")
        for color in SpaceColor.allCases {
            let colorChoice = item(color.name, #selector(ShellController.setCurrentSpaceColor(_:)), "", target: commands)
            colorChoice.image = color.swatch()
            colorChoice.representedObject = color.rawValue
            colorMenu.addItem(colorChoice)
        }
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)
        menu.addItem(.separator())
        for index in 1...9 {
            let selectItem = item("Space \(index)", #selector(ShellController.selectSpaceAtIndex(_:)), "\(index)", [.control], target: commands, symbol: "\(index).circle")
            selectItem.tag = index
            selectItem.allowsKeyEquivalentWhenHidden = true
            menu.addItem(selectItem)
        }
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", symbol: "minus.rectangle"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:)), "", [], symbol: "plus.rectangle"))
        NSApp.windowsMenu = menu
        return menu
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        _ keyEquivalent: String,
        _ modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil,
        symbol: String? = nil
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        menuItem.keyEquivalentModifierMask = modifiers
        menuItem.target = target
        menuItem.image = symbol.map(symbolImage)
        return menuItem
    }

    static func symbolImage(_ name: String) -> NSImage {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { preconditionFailure("Missing SF Symbol \(name)") }
        return image
    }

    private static func hiddenShortcut(_ menuItem: NSMenuItem) -> NSMenuItem {
        menuItem.isHidden = true
        menuItem.allowsKeyEquivalentWhenHidden = true
        return menuItem
    }
}
