public struct RowSelection<Identifier: Hashable>: Equatable {
    public private(set) var identifiers: [Identifier] = []
    public private(set) var anchor: Identifier?
    public private(set) var cursor: Identifier?

    public init() {}

    public var isMultiple: Bool { identifiers.count > 1 }

    public func contains(_ identifier: Identifier) -> Bool {
        identifiers.contains(identifier)
    }

    public mutating func clear() {
        self = RowSelection()
    }

    public mutating func toggle(_ identifier: Identifier, active: Identifier?, in order: [Identifier]) {
        var chosen = Set(identifiers.isEmpty ? [active].compactMap { $0 } : identifiers)
        if chosen.contains(identifier) {
            chosen.remove(identifier)
        } else {
            chosen.insert(identifier)
        }
        identifiers = order.filter(chosen.contains)
        anchor = identifier
        cursor = identifier
        if identifiers.count < 2 { clear() }
    }

    public mutating func extend(to identifier: Identifier, active: Identifier?, in order: [Identifier]) {
        let start = anchor ?? active ?? identifier
        guard let from = order.firstIndex(of: start), let to = order.firstIndex(of: identifier) else { return }
        identifiers = Array(order[min(from, to)...max(from, to)])
        anchor = start
        cursor = identifier
        if identifiers.count < 2 { clear() }
    }

    public mutating func extend(by offset: Int, from focused: Identifier, in order: [Identifier]) -> Identifier? {
        let current = cursor ?? focused
        guard let index = order.firstIndex(of: current) else { return nil }
        let next = order[min(max(index + offset, 0), order.count - 1)]
        let start = anchor ?? focused
        guard let from = order.firstIndex(of: start), let to = order.firstIndex(of: next) else { return nil }
        identifiers = Array(order[min(from, to)...max(from, to)])
        anchor = start
        cursor = next
        if identifiers.count < 2 {
            identifiers = []
            cursor = next
        }
        return next
    }

    public mutating func retain(_ order: [Identifier]) {
        let remaining = Set(order)
        let kept = identifiers.filter(remaining.contains)
        guard kept != identifiers else { return }
        identifiers = kept
        if let anchor, !remaining.contains(anchor) { self.anchor = nil }
        if let cursor, !remaining.contains(cursor) { self.cursor = nil }
        if identifiers.count < 2 { clear() }
    }
}
