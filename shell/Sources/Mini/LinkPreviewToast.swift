import AppKit
import ImageIO
import MiniRules

@MainActor
final class LinkPreviewCardView: NSView {
    private let preview: LinkPreview
    private let showsDiagnostics: Bool
    private let thumbnailView = NSView()
    private let captionLabel = NSTextField(labelWithString: "")

    static var width: CGFloat { InterfaceScale.scaled(300) }
    static var padding: CGFloat { InterfaceScale.scaled(12) }
    static var imageInset: CGFloat { InterfaceScale.scaled(6) }
    static var cornerRadius: CGFloat { InterfaceScale.scaled(18) }

    init(preview: LinkPreview, host: String, showsDiagnostics: Bool) {
        self.preview = preview
        self.showsDiagnostics = showsDiagnostics
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = InterfaceScale.scaled(2)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: Self.padding - (preview.imageURL == nil ? 0 : Self.imageInset), left: Self.padding, bottom: Self.padding, right: Self.padding)

        let titleLabel = NSTextField(wrappingLabelWithString: preview.title ?? host)
        titleLabel.font = .systemFont(ofSize: InterfaceScale.scaled(13), weight: .semibold)
        titleLabel.maximumNumberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.truncatesLastVisibleLine = true
        let hostLabel = NSTextField(labelWithString: host)
        hostLabel.font = InterfaceFont.tooltip
        hostLabel.textColor = .secondaryLabelColor
        hostLabel.lineBreakMode = .byTruncatingMiddle
        captionLabel.font = InterfaceFont.tooltip
        captionLabel.textColor = .tertiaryLabelColor
        captionLabel.lineBreakMode = .byTruncatingTail
        for label in [titleLabel, hostLabel, captionLabel] {
            label.preferredMaxLayoutWidth = Self.width - Self.padding * 2
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(label)
        }
        stack.setCustomSpacing(InterfaceScale.scaled(4), after: hostLabel)
        addSubview(stack)

        var constraints = [
            widthAnchor.constraint(equalToConstant: Self.width),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        if preview.imageURL != nil {
            let imageWidth = Self.width - Self.imageInset * 2
            thumbnailView.translatesAutoresizingMaskIntoConstraints = false
            thumbnailView.wantsLayer = true
            thumbnailView.layer?.cornerRadius = CornerMetrics.concentric(outer: Self.cornerRadius, inset: Self.imageInset)
            thumbnailView.layer?.cornerCurve = .continuous
            thumbnailView.layer?.masksToBounds = true
            thumbnailView.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            thumbnailView.layer?.contentsGravity = .resizeAspectFill
            addSubview(thumbnailView)
            constraints += [
                thumbnailView.topAnchor.constraint(equalTo: topAnchor, constant: Self.imageInset),
                thumbnailView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.imageInset),
                thumbnailView.widthAnchor.constraint(equalToConstant: imageWidth),
                thumbnailView.heightAnchor.constraint(equalToConstant: (imageWidth / LinkPreview.commonAspect).rounded()),
                stack.topAnchor.constraint(equalTo: thumbnailView.bottomAnchor),
            ]
        } else {
            constraints.append(stack.topAnchor.constraint(equalTo: topAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        show(.pending)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ state: LinkPreview.ImageState, image: NSImage? = nil) {
        let diagnostic = showsDiagnostics ? preview.diagnostic(image: state) : nil
        captionLabel.stringValue = diagnostic ?? ""
        captionLabel.isHidden = diagnostic == nil
        guard let image, let layer = thumbnailView.layer else { return }
        layer.backgroundColor = nil
        layer.contents = image.layerContents(forContentsScale: window?.backingScaleFactor ?? 2)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.2
        layer.add(fade, forKey: "thumbnailFade")
    }
}

enum LinkPreviewImageLoader {
    struct Loaded: Sendable {
        let data: Data
        let pixelSize: CGSize
    }

    private static let maximumBytes = 8 * 1024 * 1024

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 6
        return URLSession(configuration: configuration)
    }()

    static func load(_ url: URL) async -> Loaded? {
        var request = URLRequest(url: url)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status), data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return Loaded(data: data, pixelSize: CGSize(width: width, height: height))
    }
}

extension ShellController {
    func showLinkPreviewToast(for tab: Tab) -> Bool {
        guard let address = URL(string: tab.url), let scheme = address.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = address.host() else { return false }
        let tags = tab.linkPreviewTags ?? LinkPreviewTags(baseURL: tab.url, titleTag: tab.displayTitle)
        let preview = LinkPreview(tags)
        let displayHost = address.port.map { "\(host):\(String($0))" } ?? host
        let card = LinkPreviewCardView(preview: preview, host: displayHost, showsDiagnostics: tab.linkPreviewTags != nil)
        toast.show(card: card, cornerRadius: LinkPreviewCardView.cornerRadius, duration: 3.5)
        guard let imageURL = preview.imageURL else { return true }
        Task { @MainActor [weak card] in
            let loaded = await LinkPreviewImageLoader.load(imageURL)
            guard let card else { return }
            guard let loaded, let image = NSImage(data: loaded.data) else {
                card.show(.failed)
                return
            }
            card.show(.loaded(loaded.pixelSize), image: image)
        }
        return true
    }
}
