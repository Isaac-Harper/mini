import AppKit

enum SpaceColor: String, CaseIterable, Codable, Identifiable {
    case amber, blue, green, teal, purple, pink, red, graphite

    var id: String { rawValue }

    var name: String { rawValue.capitalized }

    var accent: NSColor { Self.accents[self]! }

    private static let accents: [SpaceColor: NSColor] = Dictionary(uniqueKeysWithValues: allCases.map { color in
        let (light, dark) = color.components
        let accent = NSColor(name: NSColor.Name("SpaceColor." + color.rawValue)) { appearance in
            let (red, green, blue) = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        }
        return (color, accent)
    })

    private var components: (light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) {
        switch self {
        case .amber: ((0.86, 0.56, 0.14), (0.96, 0.71, 0.32))
        case .blue: ((0.22, 0.49, 0.90), (0.42, 0.63, 1.00))
        case .green: ((0.26, 0.62, 0.36), (0.44, 0.80, 0.53))
        case .teal: ((0.10, 0.58, 0.62), (0.32, 0.78, 0.79))
        case .purple: ((0.53, 0.37, 0.86), (0.69, 0.56, 0.98))
        case .pink: ((0.87, 0.34, 0.58), (0.98, 0.53, 0.73))
        case .red: ((0.85, 0.31, 0.27), (0.98, 0.49, 0.43))
        case .graphite: ((0.45, 0.47, 0.52), (0.66, 0.68, 0.73))
        }
    }

    static func nextUnused(after used: [SpaceColor]) -> SpaceColor {
        allCases.first { !used.contains($0) } ?? allCases[used.count % allCases.count]
    }

    func swatch(diameter: CGFloat = 12) -> NSImage {
        let accent = accent
        return NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            accent.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
    }
}
