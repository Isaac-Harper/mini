import AppKit
import MiniRules

@MainActor
final class SiteBackgroundCache {
    private let fileURL: URL
    private var backgrounds: SiteBackgrounds
    private let writer = DispatchQueue(label: "Mini.SiteBackgroundCache", qos: .utility)

    private static let capacity = 500

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("site-backgrounds.json")
        if let data = try? Data(contentsOf: fileURL), let stored = try? JSONDecoder().decode(SiteBackgrounds.self, from: data) {
            backgrounds = stored
        } else {
            backgrounds = SiteBackgrounds(capacity: Self.capacity)
        }
    }

    func record(_ rgba: UInt32, forPageAt address: String) {
        guard let host = SitePreferences.host(of: address), let rgb = SiteBackgrounds.opaqueRGB(fromPacked: rgba),
              backgrounds.record(rgb, forHost: host) else { return }
        let data = try! JSONEncoder().encode(backgrounds)
        let fileURL = self.fileURL
        writer.async { try? data.write(to: fileURL, options: .atomic) }
    }

    func rgb(forPageAt address: String, appearance: NSAppearance) -> UInt32 {
        if let host = SitePreferences.host(of: address), let rgb = backgrounds.rgb(forHost: host) { return rgb }
        var rgb: UInt32 = 0
        appearance.performAsCurrentDrawingAppearance {
            guard let color = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) else { preconditionFailure("Window background has no sRGB form") }
            rgb = UInt32((color.redComponent * 255).rounded()) << 16 | UInt32((color.greenComponent * 255).rounded()) << 8 | UInt32((color.blueComponent * 255).rounded())
        }
        return rgb
    }
}
