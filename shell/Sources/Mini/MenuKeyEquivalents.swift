import AppKit

@MainActor
enum MenuKeyEquivalents {
    private static let standardEditActions: Set<Selector> = [
        Selector(("undo:")), Selector(("redo:")),
        #selector(ShellController.undoTabAction(_:)), #selector(ShellController.redoTabAction(_:)),
        #selector(NSText.cut(_:)), #selector(NSText.copy(_:)), #selector(NSText.paste(_:)),
        #selector(NSTextView.pasteAsPlainText(_:)), #selector(NSText.delete(_:)), #selector(NSText.selectAll(_:)),
    ]

    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    private static let tabKeyCode: UInt16 = 48

    static func undoDirection(of event: NSEvent) -> Bool? {
        guard event.type == .keyDown, key(of: event) == "z" else { return nil }
        switch event.modifierFlags.intersection(relevantModifiers) {
        case [.command]: return false
        case [.command, .shift]: return true
        default: return nil
        }
    }

    static func perform(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, let mainMenu = NSApp.mainMenu else { return false }
        let eventKey = key(of: event)
        let eventModifiers = event.modifierFlags.intersection(relevantModifiers)
        let candidates = browserCommandItems(in: mainMenu)
        let exactMatch = candidates.first { item in
            let itemKey = normalizedKeyEquivalent(of: item)
            return itemKey.key == eventKey && itemKey.modifiers == eventModifiers
        }
        let shiftedSymbolMatch = candidates.first { item in
            let itemKey = normalizedKeyEquivalent(of: item)
            return itemKey.key == eventKey
                && !itemKey.key.first!.isLetter
                && eventModifiers.contains(.shift)
                && itemKey.modifiers == eventModifiers.subtracting(.shift)
        }
        guard let item = exactMatch ?? shiftedSymbolMatch, let menu = item.menu else { return false }
        menu.update()
        guard item.isEnabled else { return false }
        menu.performActionForItem(at: menu.index(of: item))
        return true
    }

    private static func key(of event: NSEvent) -> String {
        if event.keyCode == tabKeyCode { return "\t" }
        return (event.charactersIgnoringModifiers ?? "").lowercased()
    }

    private static func normalizedKeyEquivalent(of item: NSMenuItem) -> (key: String, modifiers: NSEvent.ModifierFlags) {
        var modifiers = item.keyEquivalentModifierMask.intersection(relevantModifiers)
        let keyEquivalent = item.keyEquivalent
        if keyEquivalent != keyEquivalent.lowercased() {
            modifiers.insert(.shift)
        }
        return (keyEquivalent.lowercased(), modifiers)
    }

    private static func browserCommandItems(in menu: NSMenu) -> [NSMenuItem] {
        menu.items.flatMap { item -> [NSMenuItem] in
            if let submenu = item.submenu {
                return browserCommandItems(in: submenu)
            }
            guard !item.keyEquivalent.isEmpty,
                  !item.isHidden || item.allowsKeyEquivalentWhenHidden,
                  let action = item.action,
                  !standardEditActions.contains(action)
            else { return [] }
            return [item]
        }
    }
}
