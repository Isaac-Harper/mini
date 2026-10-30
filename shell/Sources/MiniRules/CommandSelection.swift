import CoreGraphics

public enum CommandSelection {
    public static func retainedIndex(previous: String?, in identifiers: [String], selectable: [Bool], fallback: Int?) -> Int? {
        if let previous, let index = identifiers.firstIndex(of: previous), selectable[index] {
            return index
        }
        guard let fallback else { return nil }
        return firstSelectable(atOrAfter: min(fallback, identifiers.count - 1), selectable: selectable)
            ?? lastSelectable(atOrBefore: min(fallback, identifiers.count - 1), selectable: selectable)
    }

    public static func moved(_ index: Int?, by offset: Int, selectable: [Bool], allowsNone: Bool) -> Int? {
        guard offset != 0 else { return index }
        guard let index else {
            return offset > 0 ? firstSelectable(atOrAfter: 0, selectable: selectable) : nil
        }
        if offset > 0 {
            return firstSelectable(atOrAfter: index + 1, selectable: selectable) ?? index
        }
        if let previous = lastSelectable(atOrBefore: index - 1, selectable: selectable) {
            return previous
        }
        return allowsNone ? nil : index
    }

    public static func pointerTakesSelection(at location: CGPoint, anchor: CGPoint?) -> Bool {
        guard let anchor else { return true }
        return location != anchor
    }

    public static func firstSelectable(atOrAfter start: Int, selectable: [Bool]) -> Int? {
        guard start >= 0, start < selectable.count else { return nil }
        return selectable[start...].firstIndex(of: true)
    }

    private static func lastSelectable(atOrBefore end: Int, selectable: [Bool]) -> Int? {
        guard end >= 0, end < selectable.count else { return nil }
        return selectable[...end].lastIndex(of: true)
    }
}

public enum CommandEscape: Equatable, Sendable {
    case revert
    case close

    public static func action(text: String, openingText: String) -> CommandEscape {
        text == openingText ? .close : .revert
    }
}

public enum CommandEntry: Sendable {
    case newTab
    case newChildTab
    case editCurrent
}

public enum CommandReturnModifier: Sendable {
    case none
    case command
    case option

    public init(command: Bool, option: Bool) {
        self = command ? .command : option ? .option : .none
    }
}

public enum CommandOpenTarget: Equatable, Sendable {
    case currentTab
    case newTab
    case newChildTab
    case backgroundTab

    public static func target(entry: CommandEntry, modifier: CommandReturnModifier) -> CommandOpenTarget {
        switch (modifier, entry) {
        case (.command, _): .backgroundTab
        case (.option, _): .newChildTab
        case (.none, .newTab): .newTab
        case (.none, .newChildTab): .newChildTab
        case (.none, .editCurrent): .currentTab
        }
    }
}
