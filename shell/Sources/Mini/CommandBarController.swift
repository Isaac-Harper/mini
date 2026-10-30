import AppKit
import CMiniCore
import MiniRules
import SwiftUI

@MainActor
final class CommandBarController: NSObject, NSTextFieldDelegate {
    private unowned let shell: ShellController
    private let model = CommandBarModel()
    private let dismissView = OverlayDismissView()
    private let glassView = NSGlassEffectView()
    private let field = CommandField()
    private let iconView = NSImageView()
    private let focusRing = FocusRingView()
    private let backing = CommandBarBackingView()
    private var suggestionsView: OverlayHostingView<CommandSuggestionsView>!
    private let offsetGuide = NSLayoutGuide()
    private var suggestionsHeight: NSLayoutConstraint!
    private var widthConstraint: NSLayoutConstraint!
    private var scaledConstraints: [(constraint: NSLayoutConstraint, constant: () -> CGFloat)] = []
    private let content = NSView()
    private let searchSuggestionFetcher = SearchSuggestionFetcher()
    private var mode: CommandBarMode = .newTab
    private var openingText = ""
    private var typedText = ""
    private var completion: String?
    private var pastedText: String?
    private var pastedSummary: String?
    private var returnFocusSidebarTab: MiniTabId?
    private(set) var isOpen = false

    init(shell: ShellController) {
        self.shell = shell
        super.init()
        suggestionsView = OverlayHostingView(rootView: CommandSuggestionsView(
            model: model,
            faviconLookup: { [weak shell] address in shell?.faviconCache.image(forPageAt: address) },
            activate: { [weak self] suggestion in self?.activate(suggestion, modifier: .currentEvent) }
        ))
        suggestionsView.sizingOptions = []
        buildViews()
    }

    private func buildViews() {
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = "Search or enter address"
        field.setAccessibilityLabel("Command Bar")
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.cell?.lineBreakMode = .byClipping
        field.delegate = self
        field.onCommandReturn = { [weak self] in self?.commit(.command) }
        field.onPaste = { [weak self] in
            guard let self, let text = NSPasteboard.general.string(forType: .string) else { return false }
            return self.pasteLinks(text)
        }

        iconView.contentTintColor = .secondaryLabelColor
        updateIcon()

        content.wantsLayer = true
        for view in [field, iconView, suggestionsView!, content] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        content.addSubview(iconView)
        content.addSubview(field)
        content.addSubview(suggestionsView)
        focusRing.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(focusRing)
        scaledConstraints = [
            (iconView.leadingAnchor.constraint(equalTo: content.leadingAnchor), { CommandBarMetrics.fieldInset }),
            (iconView.widthAnchor.constraint(equalToConstant: 0), { CommandBarMetrics.fieldIconWidth }),
            (field.leadingAnchor.constraint(equalTo: iconView.trailingAnchor), { CommandBarMetrics.fieldIconSpacing }),
            (field.trailingAnchor.constraint(equalTo: content.trailingAnchor), { -CommandBarMetrics.fieldInset }),
            (field.topAnchor.constraint(equalTo: content.topAnchor), { CommandBarMetrics.fieldTopInset }),
            (focusRing.leadingAnchor.constraint(equalTo: content.leadingAnchor), { CommandBarMetrics.contentInset }),
            (focusRing.trailingAnchor.constraint(equalTo: content.trailingAnchor), { -CommandBarMetrics.contentInset }),
            (focusRing.topAnchor.constraint(equalTo: content.topAnchor), { CommandBarMetrics.contentInset }),
            (focusRing.bottomAnchor.constraint(equalTo: field.bottomAnchor), { CommandBarMetrics.contentInset }),
            (suggestionsView.topAnchor.constraint(equalTo: field.bottomAnchor), { CommandBarMetrics.suggestionsTopSpacing }),
            (suggestionsView.bottomAnchor.constraint(equalTo: content.bottomAnchor), { -CommandBarMetrics.suggestionsBottomInset }),
        ]
        NSLayoutConstraint.activate(scaledConstraints.map(\.constraint) + [
            iconView.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            suggestionsView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            suggestionsView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        suggestionsHeight = suggestionsView.heightAnchor.constraint(equalToConstant: 0)
        suggestionsHeight.isActive = true
        applyInterfaceScale()

        glassView.style = .regular
        glassView.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.55)
        backing.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(backing, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            backing.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            backing.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            backing.topAnchor.constraint(equalTo: content.topAnchor),
            backing.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        glassView.contentView = content
        glassView.translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = glassView.widthAnchor.constraint(equalToConstant: CommandBarMetrics.width).withPriority(.init(999))
        NSLayoutConstraint.activate([
            widthConstraint,
            content.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            content.topAnchor.constraint(equalTo: glassView.topAnchor),
            content.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
        ])

        dismissView.translatesAutoresizingMaskIntoConstraints = false
        dismissView.addSubview(glassView)
        dismissView.onClickOutside = { [weak self] in
            self?.close(restoringWebFocus: true)
        }
        dismissView.onResize = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.fitSuggestions(animated: false) } }
        }
    }

    func applyInterfaceScale() {
        field.font = InterfaceFont.commandField
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: CommandBarMetrics.fieldIconPointSize, weight: .regular)
        focusRing.cornerRadius = CornerMetrics.concentric(outer: CommandBarMetrics.cornerRadius, inset: CommandBarMetrics.contentInset) - FocusRingMetrics.offset
        glassView.cornerRadius = CommandBarMetrics.cornerRadius
        widthConstraint?.constant = CommandBarMetrics.width
        for (constraint, constant) in scaledConstraints {
            constraint.constant = constant()
        }
        content.subviews.forEach { $0.needsDisplay = true }
        fitSuggestions(animated: false)
    }

    func open(mode: CommandBarMode) {
        guard shell.window.attachedSheet == nil else { return }
        if shell.pageFullscreen != nil {
            shell.endPageFullscreen()
        }
        if !isOpen {
            returnFocusSidebarTab = shell.sidebarKeyboard.focusedTabIdentifier
        }
        self.mode = mode
        pastedText = nil
        pastedSummary = nil
        completion = nil
        searchSuggestionFetcher.cancel()
        if !shell.window.isVisible || !shell.window.isKeyWindow {
            shell.showWindow()
        }
        openingText = mode == .editCurrent ? (shell.store.selectedTab?.url ?? "") : ""
        typedText = openingText
        field.stringValue = openingText
        shell.localServers.onChange = { [weak self] in self?.localServersChanged() }
        model.setLocalServers(shell.localServers.servers)
        withoutAnimation { showBrowse() }
        model.beginSession(pointerAt: NSEvent.mouseLocation)
        shell.localServers.refreshIfStale()
        updateIcon()
        focusRing.accent = shell.currentSpace.color.accent
        backing.needsDisplay = true
        if !isOpen {
            isOpen = true
            attach(to: shell.windowController!)
            fitSuggestions(animated: false)
            OverlayAnimation.appear(glassView, scale: 0.97, blurring: content)
            dismissView.alphaValue = 1
        } else {
            fitSuggestions(animated: true)
        }
        shell.window.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func close(restoringWebFocus: Bool) {
        guard isOpen else { return }
        isOpen = false
        searchSuggestionFetcher.cancel()
        shell.localServers.onChange = nil
        OverlayAnimation.disappear(glassView) { [weak self] in
            self?.dismissView.removeFromSuperview()
        }
        let sidebarTab = returnFocusSidebarTab
        returnFocusSidebarTab = nil
        if restoringWebFocus {
            if let sidebarTab, shell.store.tab(withIdentifier: sidebarTab) != nil, shell.windowController.isSidebarVisible, shell.windowController.focusSidebar() {
                shell.sidebarKeyboard.showsRing = true
                shell.sidebarKeyboard.focusedTabIdentifier = sidebarTab
            } else {
                shell.focusSelectedWebContent()
            }
        } else if let editor = field.currentEditor(), shell.window.firstResponder === editor {
            shell.window.makeFirstResponder(nil)
        }
    }

    private func attach(to windowController: MainWindowController) {
        guard dismissView.superview == nil else {
            dismissView.superview?.addSubview(dismissView)
            return
        }
        let rootView = windowController.rootView
        let webAreaView = windowController.webAreaView
        rootView.addSubview(dismissView)
        if offsetGuide.owningView == nil {
            rootView.addLayoutGuide(offsetGuide)
            NSLayoutConstraint.activate([
                offsetGuide.topAnchor.constraint(equalTo: webAreaView.topAnchor),
                offsetGuide.heightAnchor.constraint(equalTo: webAreaView.heightAnchor, multiplier: 0.16),
            ])
        }
        NSLayoutConstraint.activate([
            dismissView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            dismissView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            dismissView.topAnchor.constraint(equalTo: rootView.topAnchor),
            dismissView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            glassView.topAnchor.constraint(equalTo: offsetGuide.bottomAnchor),
            glassView.centerXAnchor.constraint(equalTo: webAreaView.centerXAnchor),
            glassView.widthAnchor.constraint(lessThanOrEqualTo: rootView.window!.contentView!.widthAnchor, constant: -80),
            glassView.widthAnchor.constraint(lessThanOrEqualTo: webAreaView.widthAnchor, constant: -32),
        ])
    }

    private func updateIcon() {
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbolName: String
        if pastedSummary != nil || PastedLinks.parse(trimmed).count >= 2 {
            symbolName = "square.stack"
        } else if CommandActions.isActionQuery(trimmed) {
            symbolName = "command"
        } else if !trimmed.isEmpty, case .address = completion.map({ URLInput.interpret($0) }) ?? URLInput.interpret(trimmed) {
            symbolName = "globe"
        } else {
            symbolName = "magnifyingglass"
        }
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }

    private func commit(_ modifier: CommandReturnModifier) {
        if let suggestion = model.selectedSuggestion {
            activate(suggestion, modifier: modifier)
            return
        }
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if CommandActions.isActionQuery(query) {
            return
        }
        if query.isEmpty {
            close(restoringWebFocus: true)
        } else {
            activate(.open(URLInput.interpret(query)), modifier: modifier)
        }
    }

    private func activate(_ suggestion: CommandSuggestion, modifier: CommandReturnModifier) {
        let target = CommandOpenTarget.target(entry: mode, modifier: modifier)
        switch suggestion {
        case .notice:
            return
        case .action(let action):
            guard action.isEnabled else { return }
            close(restoringWebFocus: true)
            DispatchQueue.main.async { MainActor.assumeIsolated { CommandActions.perform(action) } }
            return
        case .switchToTab(let tab):
            close(restoringWebFocus: false)
            shell.store.select(tab)
        case .openLinks(let links):
            close(restoringWebFocus: modifier == .command)
            shell.openLinks(links, inBackground: modifier == .command, nested: modifier == .option)
        case .archived(let entry):
            close(restoringWebFocus: false)
            shell.reopenArchived(entry)
        case .open(let interpretation):
            close(restoringWebFocus: target == .backgroundTab)
            shell.open(interpretation.url, target: target)
        case .searchSuggestion(let text):
            close(restoringWebFocus: target == .backgroundTab)
            shell.open(URLInput.Interpretation.search(text).url, target: target)
        case .history(let entry):
            close(restoringWebFocus: target == .backgroundTab)
            shell.open(entry.url, target: target)
        case .localServer(let server):
            close(restoringWebFocus: target == .backgroundTab)
            shell.open(server.address, target: target)
        }
        if target != .backgroundTab || suggestion.ignoresBackgroundTarget {
            shell.focusSelectedWebContent()
        }
    }

    func pasteLinks(_ text: String) -> Bool {
        let links = PastedLinks.parse(text)
        guard links.count >= 2 else { return false }
        let summary = "\(links.count) links pasted"
        pastedText = text
        pastedSummary = summary
        completion = nil
        typedText = summary
        field.stringValue = summary
        field.currentEditor()?.selectedRange = NSRange(location: (summary as NSString).length, length: 0)
        searchSuggestionFetcher.cancel()
        withoutAnimation { model.showLinks(links) }
        updateIcon()
        return true
    }

    private func localServersChanged() {
        guard isOpen else { return }
        withoutAnimation { model.setLocalServers(shell.localServers.servers) }
    }

    func controlTextDidChange(_ notification: Notification) {
        if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {
            return
        }
        shell.localServers.refreshIfStale()
        let text = field.stringValue
        if let pastedSummary, text != pastedSummary {
            pastedText = nil
            self.pastedSummary = nil
        }
        let isTypingForward = InlineCompletion.isTypingForward(previous: typedText, current: text)
        typedText = text
        completion = nil
        if pastedText == nil, CommandActions.isActionQuery(text) {
            searchSuggestionFetcher.cancel()
            withoutAnimation { model.showActions(CommandActions.ranked(CommandActions.actionQuery(of: text))) }
            updateIcon()
            return
        }
        let links = PastedLinks.parse(pastedText ?? text)
        if links.count >= 2 {
            searchSuggestionFetcher.cancel()
            withoutAnimation { model.showLinks(links) }
            updateIcon()
            return
        }
        let caretAtEnd = field.currentEditor()?.selectedRange == NSRange(location: (text as NSString).length, length: 0)
        refreshResults(allowingCompletion: isTypingForward && caretAtEnd)
    }

    private func refreshResults(allowingCompletion: Bool, removedIndex: Int? = nil) {
        let trimmed = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchSuggestionFetcher.cancel()
            withoutAnimation { showBrowse(removedIndex: removedIndex) }
            updateIcon()
            return
        }
        let store = shell.store
        let historyMatches = shell.history.store(forSpace: shell.currentSpace.id).search(trimmed, limit: 60)
        if allowingCompletion, let host = InlineCompletion.completion(for: typedText, hosts: completionHosts(history: historyMatches)) {
            completion = host
            let completed = InlineCompletion.completedText(typed: typedText, completion: host)
            let typedLength = (typedText as NSString).length
            field.stringValue = completed
            field.currentEditor()?.selectedRange = NSRange(location: typedLength, length: (completed as NSString).length - typedLength)
        }
        withoutAnimation {
            model.update(query: typedText, completion: completion, tabs: store.allTabs, playerTab: store.playerTab, selectedTab: store.selectedTab,
                         archived: shell.archive.entries, history: historyMatches, removedIndex: removedIndex)
        }
        updateIcon()
        searchSuggestionFetcher.fetch(model.trimmedQuery) { [weak self] texts, query in
            self?.withoutAnimation { self?.model.setSearchSuggestions(texts, for: query) }
        }
    }

    private func showBrowse(removedIndex: Int? = nil) {
        let store = shell.store
        let recent = shell.history.store(forSpace: shell.currentSpace.id).search("", limit: 60)
        model.showBrowse(tabs: store.allTabs, selectedTab: store.selectedTab, playerTab: store.playerTab, frequent: recent, removedIndex: removedIndex)
    }

    private func completionHosts(history: [HistoryEntry]) -> [String] {
        let tabAddresses = shell.store.allTabs.sorted { $0.lastSelectedAt > $1.lastSelectedAt }.map(\.url)
        let historyAddresses = Frecency.ranked(history, now: Date()).map(\.url)
        return (tabAddresses + historyAddresses)
            .filter { $0.hasPrefix("https://") || $0.hasPrefix("http://") }
            .compactMap { URL(string: $0)?.host() }
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
        fitSuggestions(animated: true)
    }

    private func maximumSuggestionsHeight() -> CGFloat {
        guard let webAreaView = shell.windowController?.webAreaView else { return .greatestFiniteMagnitude }
        let chrome = CommandBarMetrics.fieldTopInset + field.intrinsicContentSize.height + CommandBarMetrics.suggestionsTopSpacing + CommandBarMetrics.suggestionsBottomInset
        let available = webAreaView.bounds.height * 0.84 - CommandBarMetrics.bottomMargin - chrome
        return max(available, CommandBarMetrics.rowHeight * 2)
    }

    private func fitSuggestions(animated: Bool) {
        guard isOpen else { return }
        let height = min(CommandSuggestionsView.contentHeight(of: model.rows), maximumSuggestionsHeight())
        guard abs(height - suggestionsHeight.constant) > 0.5 else { return }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            suggestionsHeight.constant = height
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            suggestionsHeight.animator().constant = height
            glassView.superview?.layoutSubtreeIfNeeded()
        }
    }

    private func moveSelection(by offset: Int) {
        model.moveSelection(by: offset)
        announceSelection()
    }

    private func announceSelection() {
        guard NSWorkspace.shared.isVoiceOverEnabled, let suggestion = model.selectedSuggestion else { return }
        NSAccessibility.post(element: field, notification: .announcementRequested,
                             userInfo: [.announcement: suggestion.spokenDescription, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func acceptCompletion() -> Bool {
        guard completion != nil, let editor = field.currentEditor() else { return false }
        let length = (field.stringValue as NSString).length
        guard editor.selectedRange.length > 0, NSMaxRange(editor.selectedRange) == length else { return false }
        editor.selectedRange = NSRange(location: length, length: 0)
        typedText = field.stringValue
        return true
    }

    private func revertOrClose() {
        switch CommandEscape.action(text: field.stringValue, openingText: openingText) {
        case .close:
            close(restoringWebFocus: true)
        case .revert:
            pastedText = nil
            pastedSummary = nil
            completion = nil
            typedText = openingText
            field.stringValue = openingText
            searchSuggestionFetcher.cancel()
            withoutAnimation { showBrowse() }
            model.beginSession(pointerAt: NSEvent.mouseLocation)
            updateIcon()
            field.currentEditor()?.selectAll(nil)
        }
    }

    private func removeSelectedRow() -> Bool {
        guard let index = model.selectedIndex, let suggestion = model.removableSelection else { return false }
        switch suggestion {
        case .switchToTab(let tab):
            shell.performUndoable("Close Tab") { shell.store.close(tab) }
        case .history(let entry):
            shell.history.store(forSpace: shell.currentSpace.id).delete(url: entry.url)
        case .archived(let entry):
            shell.archive.remove(entry)
        default:
            return false
        }
        refreshResults(allowingCompletion: false, removedIndex: index)
        return true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.insertBacktab(_:)):
            moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
        case #selector(NSResponder.insertTab(_:)):
            if !acceptCompletion() { moveSelection(by: 1) }
        case #selector(NSResponder.insertNewline(_:)):
            commit(.currentEvent)
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            commit(.option)
        case #selector(NSResponder.deleteToBeginningOfLine(_:)), #selector(NSResponder.deleteToEndOfLine(_:)):
            return removeSelectedRow()
        case #selector(NSResponder.cancelOperation(_:)):
            revertOrClose()
        default:
            return false
        }
        return true
    }
}

extension CommandReturnModifier {
    @MainActor static var currentEvent: CommandReturnModifier {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        return CommandReturnModifier(command: flags.contains(.command), option: flags.contains(.option))
    }
}

@MainActor
private extension CommandSuggestion {
    var ignoresBackgroundTarget: Bool {
        switch self {
        case .switchToTab, .archived, .action, .notice: true
        case .open, .searchSuggestion, .history, .localServer, .openLinks: false
        }
    }
}

final class CommandField: NSTextField {
    var onCommandReturn: (() -> Void)?
    var onPaste: (() -> Bool)?

    private static let returnKeyCodes: Set<UInt16> = [36, 76]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, Self.returnKeyCodes.contains(event.keyCode), currentEditor() != nil {
            onCommandReturn?()
            return true
        }
        if modifiers == .command, event.charactersIgnoringModifiers == "v", currentEditor() != nil, onPaste?() == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class OverlayDismissView: NSView {
    var onClickOutside: (() -> Void)?
    var onResize: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onResize?()
    }

    override func mouseDown(with event: NSEvent) {
        onClickOutside?()
    }
}

final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { false }
}

extension NSLayoutConstraint {
    func withPriority(_ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

private final class CommandBarBackingView: NSView {
    private static let opacity: CGFloat = 0.72

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let workspace = NSWorkspace.shared
        layer?.cornerRadius = CommandBarMetrics.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(workspace.accessibilityDisplayShouldReduceTransparency ? 1 : Self.opacity).cgColor
        layer?.borderWidth = workspace.accessibilityDisplayShouldIncreaseContrast ? 1 : 0
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
