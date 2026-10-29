import Foundation

public struct SourceToken: Equatable, Sendable {
    public enum Kind: Sendable {
        case tag
        case attribute
        case value
        case comment
        case doctype
        case entity
        case keyword
        case string
        case number
        case property
    }

    public let kind: Kind
    public let location: Int
    public let length: Int

    public init(_ kind: Kind, _ location: Int, _ length: Int) {
        self.kind = kind
        self.location = location
        self.length = length
    }
}

public enum SourceHighlighting {
    public static func tokens(ofHTML source: String) -> [SourceToken] {
        var scanner = Scanner(Array(source.utf16))
        scanner.scanHTML()
        return scanner.tokens
    }

    public static func tokens(ofScript source: String) -> [SourceToken] {
        var scanner = Scanner(Array(source.utf16))
        scanner.scanScript(upTo: scanner.units.count)
        return scanner.tokens
    }

    public static func tokens(ofStyle source: String) -> [SourceToken] {
        var scanner = Scanner(Array(source.utf16))
        scanner.scanStyle(upTo: scanner.units.count)
        return scanner.tokens
    }

    static let scriptKeywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "export",
        "extends", "false", "finally", "for", "function", "if", "import", "in", "instanceof", "let", "new", "null", "of", "return", "static",
        "super", "switch", "this", "throw", "true", "try", "typeof", "undefined", "var", "void", "while", "with", "yield",
    ]
}

private struct Scanner {
    let units: [UInt16]
    var position = 0
    var tokens: [SourceToken] = []

    init(_ units: [UInt16]) {
        self.units = units
    }

    private static let lessThan = UInt16(UInt8(ascii: "<"))
    private static let greaterThan = UInt16(UInt8(ascii: ">"))
    private static let slash = UInt16(UInt8(ascii: "/"))
    private static let equals = UInt16(UInt8(ascii: "="))
    private static let ampersand = UInt16(UInt8(ascii: "&"))
    private static let semicolon = UInt16(UInt8(ascii: ";"))
    private static let exclamation = UInt16(UInt8(ascii: "!"))
    private static let doubleQuote = UInt16(UInt8(ascii: "\""))
    private static let singleQuote = UInt16(UInt8(ascii: "'"))
    private static let backtick = UInt16(UInt8(ascii: "`"))
    private static let backslash = UInt16(UInt8(ascii: "\\"))
    private static let asterisk = UInt16(UInt8(ascii: "*"))
    private static let newline = UInt16(UInt8(ascii: "\n"))
    private static let at = UInt16(UInt8(ascii: "@"))
    private static let colon = UInt16(UInt8(ascii: ":"))
    private static let openBrace = UInt16(UInt8(ascii: "{"))
    private static let closeBrace = UInt16(UInt8(ascii: "}"))
    private static let hash = UInt16(UInt8(ascii: "#"))
    private static let dot = UInt16(UInt8(ascii: "."))
    private static let minus = UInt16(UInt8(ascii: "-"))

    private static func isLetter(_ unit: UInt16) -> Bool {
        (65...90).contains(unit) || (97...122).contains(unit)
    }

    private static func isDigit(_ unit: UInt16) -> Bool {
        (48...57).contains(unit)
    }

    private static func isIdentifier(_ unit: UInt16) -> Bool {
        isLetter(unit) || isDigit(unit) || unit == 95 || unit == 36 || unit >= 128
    }

    private static func isSpace(_ unit: UInt16) -> Bool {
        unit == 32 || unit == 9 || unit == 10 || unit == 13 || unit == 12
    }

    private func at(_ offset: Int) -> UInt16? {
        let index = position + offset
        return index < units.count ? units[index] : nil
    }

    private func starts(with text: String, at index: Int, ignoringCase: Bool = false) -> Bool {
        let pattern = Array(text.utf16)
        guard index + pattern.count <= units.count else { return false }
        for (offset, unit) in pattern.enumerated() {
            var candidate = units[index + offset]
            if ignoringCase, (65...90).contains(candidate) { candidate += 32 }
            if candidate != unit { return false }
        }
        return true
    }

    private func index(of text: String, from start: Int, limit: Int, ignoringCase: Bool = false) -> Int? {
        var index = start
        while index < limit {
            if starts(with: text, at: index, ignoringCase: ignoringCase) { return index }
            index += 1
        }
        return nil
    }

    private mutating func emit(_ kind: SourceToken.Kind, from start: Int, to end: Int) {
        if end > start { tokens.append(SourceToken(kind, start, end - start)) }
    }

    mutating func scanHTML() {
        while position < units.count {
            let unit = units[position]
            if unit == Self.lessThan {
                if starts(with: "<!--", at: position) {
                    let end = index(of: "-->", from: position + 4, limit: units.count).map { $0 + 3 } ?? units.count
                    emit(.comment, from: position, to: end)
                    position = end
                } else if at(1) == Self.exclamation {
                    let end = index(of: ">", from: position, limit: units.count).map { $0 + 1 } ?? units.count
                    emit(.doctype, from: position, to: end)
                    position = end
                } else if let next = at(1), Self.isLetter(next) || (next == Self.slash && at(2).map(Self.isLetter) == true) {
                    scanTag()
                } else {
                    position += 1
                }
            } else if unit == Self.ampersand {
                scanEntity()
            } else {
                position += 1
            }
        }
    }

    private mutating func scanEntity() {
        var end = position + 1
        while end < units.count, end - position <= 32, Self.isIdentifier(units[end]) || units[end] == Self.hash { end += 1 }
        if end < units.count, units[end] == Self.semicolon, end > position + 1 {
            emit(.entity, from: position, to: end + 1)
            position = end + 1
        } else {
            position += 1
        }
    }

    private mutating func scanTag() {
        let start = position
        let isClosing = at(1) == Self.slash
        position += isClosing ? 2 : 1
        let nameStart = position
        while position < units.count, !Self.isSpace(units[position]), units[position] != Self.greaterThan, units[position] != Self.slash { position += 1 }
        let name = String(decoding: units[nameStart..<position], as: UTF16.self).lowercased()
        emit(.tag, from: start, to: position)
        var selfClosing = false
        while position < units.count {
            let unit = units[position]
            if Self.isSpace(unit) {
                position += 1
            } else if unit == Self.greaterThan {
                emit(.tag, from: position, to: position + 1)
                position += 1
                break
            } else if unit == Self.slash, at(1) == Self.greaterThan {
                emit(.tag, from: position, to: position + 2)
                position += 2
                selfClosing = true
                break
            } else if unit == Self.equals {
                position += 1
                scanAttributeValue()
            } else {
                let attributeStart = position
                while position < units.count, !Self.isSpace(units[position]), units[position] != Self.equals, units[position] != Self.greaterThan,
                      !(units[position] == Self.slash && at(1) == Self.greaterThan) { position += 1 }
                emit(.attribute, from: attributeStart, to: max(position, attributeStart + 1))
                position = max(position, attributeStart + 1)
            }
        }
        guard !isClosing, !selfClosing, name == "script" || name == "style" else { return }
        let end = index(of: "</" + name, from: position, limit: units.count, ignoringCase: true) ?? units.count
        if name == "script" { scanScript(upTo: end) } else { scanStyle(upTo: end) }
        position = end
    }

    private mutating func scanAttributeValue() {
        while position < units.count, Self.isSpace(units[position]) { position += 1 }
        guard position < units.count else { return }
        let start = position
        let quote = units[position]
        if quote == Self.doubleQuote || quote == Self.singleQuote {
            position += 1
            while position < units.count, units[position] != quote { position += 1 }
            position = min(position + 1, units.count)
        } else {
            while position < units.count, !Self.isSpace(units[position]), units[position] != Self.greaterThan { position += 1 }
        }
        emit(.value, from: start, to: position)
    }

    private mutating func scanQuoted(upTo limit: Int) {
        let start = position
        let quote = units[position]
        position += 1
        while position < limit {
            let current = units[position]
            if current == quote {
                position += 1
                break
            }
            if current == Self.newline, quote != Self.backtick { break }
            position += current == Self.backslash ? 2 : 1
        }
        position = min(position, limit)
        emit(.string, from: start, to: position)
    }

    private mutating func scanBlockComment(upTo limit: Int) {
        let end = index(of: "*/", from: position + 2, limit: limit).map { $0 + 2 } ?? limit
        emit(.comment, from: position, to: min(end, limit))
        position = min(end, limit)
    }

    private mutating func scanNumber(upTo limit: Int) {
        let start = position
        while position < limit, Self.isIdentifier(units[position]) || units[position] == Self.dot { position += 1 }
        emit(.number, from: start, to: position)
    }

    mutating func scanScript(upTo limit: Int) {
        while position < limit {
            let unit = units[position]
            if unit == Self.doubleQuote || unit == Self.singleQuote || unit == Self.backtick {
                scanQuoted(upTo: limit)
            } else if unit == Self.slash, position + 1 < limit, units[position + 1] == Self.slash {
                let end = index(of: "\n", from: position, limit: limit) ?? limit
                emit(.comment, from: position, to: end)
                position = end
            } else if unit == Self.slash, position + 1 < limit, units[position + 1] == Self.asterisk {
                scanBlockComment(upTo: limit)
            } else if Self.isDigit(unit) {
                scanNumber(upTo: limit)
            } else if Self.isIdentifier(unit) {
                let start = position
                while position < limit, Self.isIdentifier(units[position]) { position += 1 }
                let word = String(decoding: units[start..<position], as: UTF16.self)
                if SourceHighlighting.scriptKeywords.contains(word) { emit(.keyword, from: start, to: position) }
            } else {
                position += 1
            }
        }
    }

    mutating func scanStyle(upTo limit: Int) {
        var depth = 0
        while position < limit {
            let unit = units[position]
            if unit == Self.doubleQuote || unit == Self.singleQuote {
                scanQuoted(upTo: limit)
            } else if unit == Self.slash, position + 1 < limit, units[position + 1] == Self.asterisk {
                scanBlockComment(upTo: limit)
            } else if unit == Self.openBrace {
                depth += 1
                position += 1
            } else if unit == Self.closeBrace {
                depth = max(0, depth - 1)
                position += 1
            } else if unit == Self.at {
                let start = position
                position += 1
                while position < limit, Self.isIdentifier(units[position]) || units[position] == Self.minus { position += 1 }
                emit(.keyword, from: start, to: position)
            } else if Self.isDigit(unit) {
                scanNumber(upTo: limit)
            } else if depth > 0, Self.isLetter(unit) || unit == Self.minus {
                let start = position
                while position < limit, Self.isIdentifier(units[position]) || units[position] == Self.minus { position += 1 }
                var lookahead = position
                while lookahead < limit, Self.isSpace(units[lookahead]) { lookahead += 1 }
                if lookahead < limit, units[lookahead] == Self.colon { emit(.property, from: start, to: position) }
            } else {
                position += 1
            }
        }
    }
}
