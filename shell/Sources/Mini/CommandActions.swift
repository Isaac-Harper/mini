import AppKit
import MiniRules

struct CommandAction: Identifiable {
    let id: String
    let title: String
    let image: NSImage?
    let shortcut: String
    let isEnabled: Bool
    let isOn: Bool
    weak var item: NSMenuItem?
}

@MainActor
enum CommandActions {
    static let prefix = ">"

    private static let recentKey = "RecentCommandActions"
    private static let recentLimit = 8

    private static let excludedActions: Set<Selector> = [
        Selector(("undo:")), Selector(("redo:")),
        #selector(NSText.cut(_:)), #selector(NSText.copy(_:)), #selector(NSText.paste(_:)),
        #selector(NSTextView.pasteAsPlainText(_:)), #selector(NSText.delete(_:)), #selector(NSText.selectAll(_:)),
        #selector(ShellController.selectTabAtIndex(_:)), #selector(ShellController.newTab(_:)), #selector(ShellController.openLocation(_:)),
    ]

    static func isActionQuery(_ text: String) -> Bool {
        text.hasPrefix(prefix)
    }

    static func actionQuery(of text: String) -> String {
        String(text.dropFirst(prefix.count))
    }

    static func ranked(_ query: String) -> [CommandAction] {
        guard let mainMenu = NSApp.mainMenu else { return [] }
        let actions = collect(in: mainMenu, path: [])
        return FuzzyMatch.rank(actions, query: query, title: \.title, identifier: \.id, recent: recent)
    }

    static func perform(_ action: CommandAction) {
        guard let item = action.item, let menu = item.menu else { return }
        menu.update()
        guard item.isEnabled else { return }
        UserDefaults.standard.set(FuzzyMatch.remembering(action.id, in: recent, limit: recentLimit), forKey: recentKey)
        menu.performActionForItem(at: menu.index(of: item))
    }

    private static var recent: [String] {
        UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    private static func collect(in menu: NSMenu, path: [String]) -> [CommandAction] {
        menu.update()
        return menu.items.flatMap { item -> [CommandAction] in
            if let submenu = item.submenu {
                let title = submenu.title.isEmpty ? item.title : submenu.title
                return collect(in: submenu, path: path.isEmpty && menu === NSApp.mainMenu ? [] : path + [title])
            }
            guard !item.isSeparatorItem, !item.isHidden, !item.title.isEmpty, let action = item.action, !excludedActions.contains(action) else { return [] }
            let modifiers = item.keyEquivalentModifierMask
            return [CommandAction(
                id: "\(NSStringFromSelector(action))|\(item.tag)|\((item.representedObject as? String) ?? "")",
                title: (path + [item.title]).joined(separator: ": "),
                image: item.image,
                shortcut: KeyEquivalentText.describe(key: item.keyEquivalent, control: modifiers.contains(.control), option: modifiers.contains(.option),
                                                     shift: modifiers.contains(.shift), command: modifiers.contains(.command)),
                isEnabled: item.isEnabled,
                isOn: item.state == .on,
                item: item
            )]
        }
    }
}
