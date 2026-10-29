import Foundation

public enum KeyEquivalentText {
    public static func describe(key: String, control: Bool, option: Bool, shift: Bool, command: Bool) -> String {
        guard !key.isEmpty else { return "" }
        var shifted = shift
        if key != key.lowercased() { shifted = true }
        let modifiers = (control ? "\u{2303}" : "") + (option ? "\u{2325}" : "") + (shifted ? "\u{21E7}" : "") + (command ? "\u{2318}" : "")
        return modifiers + symbol(for: key)
    }

    private static func symbol(for key: String) -> String {
        switch key.unicodeScalars.first?.value {
        case 0x09: "\u{21E5}"
        case 0x0D, 0x03: "\u{21A9}"
        case 0x1B: "\u{238B}"
        case 0x08, 0x7F: "\u{232B}"
        case 0x20: "Space"
        case 0xF700: "\u{2191}"
        case 0xF701: "\u{2193}"
        case 0xF702: "\u{2190}"
        case 0xF703: "\u{2192}"
        default: key.uppercased()
        }
    }
}
