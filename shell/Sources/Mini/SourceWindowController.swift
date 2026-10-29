import AppKit
import CMiniCore
import MiniRules

@MainActor
final class SourceWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static var openControllers: [SourceWindowController] = []
    private static var pendingRequests: [UInt64: SourceWindowController] = [:]
    private static var nextRequest: UInt64 = 1

    private static let wrapItemIdentifier = NSToolbarItem.Identifier("SourceWrapLines")
    private static let attributeBatchSize = 20_000
    private static let fontSize: CGFloat = 12
    private static let wrapsLinesKey = "SourceWrapsLines"

    private let textView = NSTextView(usingTextLayoutManager: false)
    private let scrollView = NSScrollView()
    private let lineNumbers: LineNumberRulerView
    private let wrapButton = NSButton()
    private var wrapsLines = UserDefaults.standard.object(forKey: SourceWindowController.wrapsLinesKey) as? Bool ?? true

    static func show(sourceOf tab: Tab) {
        guard tab.hasBrowser else { return }
        let controller = SourceWindowController(address: tab.url)
        let request = nextRequest
        nextRequest += 1
        pendingRequests[request] = controller
        openControllers.append(controller)
        controller.showWindow(nil)
        mini_browser_request_source(tab.id, request)
    }

    static func sourceReceived(request: UInt64, source: String) {
        pendingRequests.removeValue(forKey: request)?.display(source)
    }

    static var keyController: SourceWindowController? {
        openControllers.first { $0.window?.isKeyWindow == true }
    }

    static var font: NSFont {
        NSFont(name: "GeistMono-Regular", size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private init(address: String) {
        lineNumbers = LineNumberRulerView(scrollView: scrollView, textView: textView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 680), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Source of \(URLInput.host(of: address) ?? address)"
        window.subtitle = address
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 240)
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        buildViews(in: window)
        if let main = NSApp.mainWindow {
            window.setFrameTopLeftPoint(NSPoint(x: main.frame.minX + 60, y: main.frame.maxY - 60))
        } else {
            window.center()
        }
    }

    required init?(coder: NSCoder) {
        preconditionFailure("SourceWindowController is built in code")
    }

    private func buildViews(in window: NSWindow) {
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = Self.font
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.isAutomaticLinkDetectionEnabled = false
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.string = "Loading source\u{2026}"
        textView.textColor = .secondaryLabelColor
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.verticalRulerView = lineNumbers
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        window.contentView = scrollView
        applyWrapping()

        let toolbar = NSToolbar(identifier: "SourceToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
    }

    private func display(_ source: String) {
        textView.textColor = .labelColor
        textView.string = source
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        lineNumbers.lineStarts = [0]
        Task.detached(priority: .userInitiated) {
            let tokens = SourceHighlighting.tokens(ofHTML: source)
            let lineStarts = LineNumberRulerView.lineStarts(of: source)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.lineNumbers.lineStarts = lineStarts
                self.applyHighlighting(tokens[...])
            }
        }
    }

    private func applyHighlighting(_ tokens: ArraySlice<SourceToken>) {
        guard let storage = textView.textStorage, !tokens.isEmpty else { return }
        let batch = tokens.prefix(Self.attributeBatchSize)
        let length = storage.length
        storage.beginEditing()
        for token in batch where token.location + token.length <= length {
            storage.addAttribute(.foregroundColor, value: Self.color(for: token.kind), range: NSRange(location: token.location, length: token.length))
        }
        storage.endEditing()
        let rest = tokens.dropFirst(Self.attributeBatchSize)
        guard !rest.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.applyHighlighting(rest) }
        }
    }

    private static func color(for kind: SourceToken.Kind) -> NSColor {
        switch kind {
        case .tag: .systemPink
        case .attribute: .systemOrange
        case .value: .systemBlue
        case .comment: .secondaryLabelColor
        case .doctype: .tertiaryLabelColor
        case .entity: .systemGreen
        case .keyword: .systemPurple
        case .string: .systemRed
        case .number: .systemIndigo
        case .property: .systemTeal
        }
    }

    private func applyWrapping() {
        guard let container = textView.textContainer else { preconditionFailure("source text view has no container") }
        if wrapsLines {
            textView.isHorizontallyResizable = false
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
            textView.frame.size.width = scrollView.contentSize.width
            scrollView.hasHorizontalScroller = false
        } else {
            textView.isHorizontallyResizable = true
            container.widthTracksTextView = false
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            scrollView.hasHorizontalScroller = true
        }
        wrapButton.state = wrapsLines ? .on : .off
        lineNumbers.needsDisplay = true
    }

    @objc private func toggleWrapping(_ sender: Any?) {
        wrapsLines.toggle()
        UserDefaults.standard.set(wrapsLines, forKey: Self.wrapsLinesKey)
        applyWrapping()
    }

    func performFind(_ action: NSTextFinder.Action) {
        let sender = NSMenuItem()
        sender.tag = action.rawValue
        window?.makeFirstResponder(textView)
        textView.performTextFinderAction(sender)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.wrapItemIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.wrapItemIdentifier]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.wrapItemIdentifier else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        wrapButton.setButtonType(.pushOnPushOff)
        wrapButton.bezelStyle = .toolbar
        wrapButton.image = NSImage(systemSymbolName: "arrow.turn.down.left", accessibilityDescription: "Wrap Lines")
        wrapButton.target = self
        wrapButton.action = #selector(toggleWrapping(_:))
        wrapButton.state = wrapsLines ? .on : .off
        wrapButton.toolTip = "Wrap Lines"
        item.view = wrapButton
        item.label = "Wrap Lines"
        return item
    }

    func windowWillClose(_ notification: Notification) {
        Self.openControllers.removeAll { $0 === self }
        Self.pendingRequests = Self.pendingRequests.filter { $0.value !== self }
    }
}

@MainActor
final class LineNumberRulerView: NSRulerView {
    private unowned let textView: NSTextView
    var lineStarts: [Int] = [0] {
        didSet { updateThickness() }
    }

    private static let padding: CGFloat = 8

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 36
        NotificationCenter.default.addObserver(self, selector: #selector(contentChanged(_:)), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(contentChanged(_:)), name: NSText.didChangeNotification, object: textView)
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    required init(coder: NSCoder) {
        preconditionFailure("LineNumberRulerView is built in code")
    }

    nonisolated static func lineStarts(of text: String) -> [Int] {
        var starts = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 10 { starts.append(offset) }
        }
        return starts
    }

    @objc private func contentChanged(_ notification: Notification) {
        needsDisplay = true
    }

    private var numberAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: SourceWindowController.font.pointSize - 1, weight: .regular), .foregroundColor: NSColor.tertiaryLabelColor]
    }

    private func updateThickness() {
        let widest = ("\(lineStarts.count)" as NSString).size(withAttributes: numberAttributes).width
        ruleThickness = ceil(widest + Self.padding * 2)
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        guard let layoutManager = textView.layoutManager, let container = textView.textContainer, lineStarts.count > 1 || textView.string.utf16.count > 0 else { return }
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        var lineIndex = Self.lineIndex(containing: characterRange.location, in: lineStarts)
        let attributes = numberAttributes
        let origin = convert(NSPoint.zero, from: textView).y
        let length = textView.string.utf16.count
        while lineIndex < lineStarts.count, lineStarts[lineIndex] <= NSMaxRange(characterRange), lineStarts[lineIndex] <= length {
            let start = lineStarts[lineIndex]
            let fragment: NSRect
            if start == length {
                fragment = layoutManager.extraLineFragmentRect
            } else {
                fragment = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: start), effectiveRange: nil)
            }
            let label = "\(lineIndex + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            let y = origin + fragment.minY + textView.textContainerInset.height + (fragment.height - size.height) / 2
            label.draw(at: NSPoint(x: ruleThickness - Self.padding - size.width, y: y), withAttributes: attributes)
            lineIndex += 1
        }
    }

    private static func lineIndex(containing location: Int, in starts: [Int]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= location { low = middle } else { high = middle - 1 }
        }
        return low
    }
}
