import AppKit
import MiniRules

@MainActor
final class ColorPickToastCardView: NSView {
    static var swatchSize: CGFloat { InterfaceScale.scaled(40) }

    init(color: NSColor, oklch: String, hex: String) {
        super.init(frame: .zero)
        let inset = LinkPreviewCardView.imageInset
        let swatch = NSView()
        swatch.translatesAutoresizingMaskIntoConstraints = false
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = CornerMetrics.concentric(outer: LinkPreviewCardView.cornerRadius, inset: inset)
        swatch.layer?.cornerCurve = .continuous
        swatch.layer?.backgroundColor = color.cgColor
        swatch.layer?.borderWidth = 1
        swatch.layer?.borderColor = NSColor.separatorColor.cgColor

        let oklchLabel = NSTextField(labelWithString: oklch)
        oklchLabel.font = .monospacedDigitSystemFont(ofSize: InterfaceScale.scaled(13), weight: .medium)
        let hexLabel = NSTextField(labelWithString: hex)
        hexLabel.font = .monospacedDigitSystemFont(ofSize: InterfaceScale.scaled(11), weight: .regular)
        hexLabel.textColor = .secondaryLabelColor
        let texts = NSStackView(views: [oklchLabel, hexLabel])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = InterfaceScale.scaled(2)
        texts.translatesAutoresizingMaskIntoConstraints = false

        addSubview(swatch)
        addSubview(texts)
        NSLayoutConstraint.activate([
            swatch.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            swatch.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            swatch.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
            swatch.widthAnchor.constraint(equalToConstant: Self.swatchSize),
            swatch.heightAnchor.constraint(equalToConstant: Self.swatchSize),
            texts.leadingAnchor.constraint(equalTo: swatch.trailingAnchor, constant: InterfaceScale.scaled(10)),
            texts.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -LinkPreviewCardView.padding),
            texts.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

extension ShellController {
    private static var activeColorSampler: NSColorSampler?

    func pickColor() {
        let sampler = NSColorSampler()
        Self.activeColorSampler = sampler
        sampler.show { [weak self] color in
            MainActor.assumeIsolated {
                Self.activeColorSampler = nil
                if let color { self?.copyPickedColor(color) }
            }
        }
    }

    func copyPickedColor(_ color: NSColor) {
        guard let converted = color.usingColorSpace(.sRGB) else { preconditionFailure("Picked color has no sRGB representation") }
        let red = min(max(converted.redComponent, 0), 1)
        let green = min(max(converted.greenComponent, 0), 1)
        let blue = min(max(converted.blueComponent, 0), 1)
        let oklch = TextStyle.oklch(red: red, green: green, blue: blue, alpha: converted.alphaComponent)
        let hex = ColorHex.string(red: red, green: green, blue: blue)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(oklch, forType: .string)
        toast.show(card: ColorPickToastCardView(color: converted, oklch: oklch, hex: hex), cornerRadius: LinkPreviewCardView.cornerRadius, duration: 3.5)
    }
}
