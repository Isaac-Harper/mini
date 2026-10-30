import AppKit
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
    private var suggestionsView: OverlayHostingView<CommandSuggestionsView>!
    private let offsetGuide = NSLayoutGuide()
    private var suggestionsHeight: NSLayoutConstraint!
    private let content = NSView()
    private let searchSuggestionFetcher = SearchSuggestionFetcher()
    private var mode: CommandBarMode = .newTab
    private var pastedText: String?
    private var pastedSummary: String?
    private(set) var isOpen = false

    private static let width: CGFloat = 760

    init(shell: ShellController) {
        self.shell = shell
        super.init()
        suggestionsView = OverlayHostingView(rootView: CommandSuggestionsView(
            model: model,
            faviconLookup: { [weak shell] address in shell?.faviconCache.image(forPageAt: address) },
            activate: { [weak self] suggestion in self?.activate(suggestion) }
        ))
        suggestionsView.sizingOptions = [.intrinsicContentSize]
        buildViews()
    }

    private func buildViews() {
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 20)
        field.placeholderString = "Search or enter address"
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        field.onCommandReturn = { [weak self] in self?.openTypedInputInBackground() }
        field.onPaste = { [weak self] in
            guard let self, let text = NSPasteboard.general.string(forType: .string) else { return false }
            return self.pasteLinks(text)
        }

        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: CommandBarMetrics.fieldIconPointSize, weight: .regular)
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
        focusRing.cornerRadius = CornerMetrics.concentric(outer: CommandBarMetrics.cornerRadius, inset: CommandBarMetrics.contentInset) - FocusRingMetrics.offset
        content.addSubview(focusRing)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: CommandBarMetrics.fieldInset),
            iconView.widthAnchor.constraint(equalToConstant: CommandBarMetrics.fieldIconWidth),
            iconView.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: CommandBarMetrics.fieldIconSpacing),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -CommandBarMetrics.fieldInset),
            field.topAnchor.constraint(equalTo: content.topAnchor, constant: CommandBarMetrics.fieldTopInset),
            focusRing.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: CommandBarMetrics.contentInset),
            focusRing.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -CommandBarMetrics.contentInset),
            focusRing.topAnchor.constraint(equalTo: content.topAnchor, constant: CommandBarMetrics.contentInset),
            focusRing.bottomAnchor.constraint(equalTo: field.bottomAnchor, constant: CommandBarMetrics.contentInset),
            suggestionsView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            suggestionsView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            suggestionsView.topAnchor.constraint(equalTo: field.bottomAnchor, constant: CommandBarMetrics.suggestionsTopSpacing),
            suggestionsView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -CommandBarMetrics.suggestionsBottomInset),
        ])
        suggestionsHeight = suggestionsView.heightAnchor.constraint(equalToConstant: 0)
        suggestionsHeight.isActive = true

        glassView.cornerRadius = CommandBarMetrics.cornerRadius
        glassView.style = .regular
        glassView.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.55)
        let backing = CommandBarBackingView()
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
        NSLayoutConstraint.activate([
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
    }

    func open(mode: CommandBarMode) {
        self.mode = mode
        pastedText = nil
        pastedSummary = nil
        if !shell.window.isVisible {
            shell.showWindow()
        }
        let store = shell.store
        field.stringValue = mode == .editCurrent ? (store.selectedTab?.url ?? "") : ""
        if mode == .editCurrent {
            model.clear()
        } else {
            model.showRecentTabs(from: store.allTabs, excluding: store.selectedTab)
        }
        updateIcon()
        focusRing.accent = shell.currentSpace.color.accent
        shell.localServers.onChange = { [weak self] in self?.localServersChanged() }
        model.setLocalServers(shell.localServers.servers)
        shell.localServers.refreshIfStale()
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
        OverlayAnimation.disappear(glassView) { [weak self] in
            self?.dismissView.removeFromSuperview()
        }
        if restoringWebFocus {
            shell.focusSelectedWebContent()
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
            glassView.widthAnchor.constraint(equalToConstant: Self.width).withPriority(.init(999)),
            glassView.widthAnchor.constraint(lessThanOrEqualTo: rootView.window!.contentView!.widthAnchor, constant: -80),
            glassView.widthAnchor.constraint(lessThanOrEqualTo: webAreaView.widthAnchor, constant: -32),
        ])
    }

    private func updateIcon() {
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbolName: String
        if CommandActions.isActionQuery(trimmed) {
            symbolName = "command"
        } else if !trimmed.isEmpty, case .address = URLInput.interpret(trimmed) {
            symbolName = "globe"
        } else {
            symbolName = "magnifyingglass"
        }
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }

    private func activate(_ suggestion: CommandSuggestion) {
        if case .action(let action) = suggestion {
            guard action.isEnabled else { return }
            close(restoringWebFocus: true)
            DispatchQueue.main.async { MainActor.assumeIsolated { CommandActions.perform(action) } }
            return
        }
        let mode = self.mode
        close(restoringWebFocus: false)
        switch suggestion {
        case .switchToTab(let tab):
            shell.store.select(tab)
        case .open(let interpretation):
            shell.open(interpretation.url, from: mode)
        case .searchSuggestion(let text):
            shell.open(URLInput.Interpretation.search(text).url, from: mode)
        case .archived(let entry):
            shell.reopenArchived(entry)
        case .history(let entry):
            shell.open(entry.url, from: mode)
        case .openLinks(let links):
            shell.openLinks(links, inBackground: false, nested: NSApp.currentEvent?.modifierFlags.contains(.option) == true)
        case .localServer(let server):
            shell.open(server.address, from: mode)
        case .action:
            preconditionFailure("actions are performed before the switch")
        }
        shell.focusSelectedWebContent()
    }

    private func openTypedInputInBackground() {
        if case .openLinks(let links) = model.selectedSuggestion {
            close(restoringWebFocus: true)
            shell.openLinks(links, inBackground: true, nested: false)
            return
        }
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !CommandActions.isActionQuery(query) else { return }
        close(restoringWebFocus: true)
        shell.openInBackground(URLInput.interpret(query).url)
    }

    func pasteLinks(_ text: String) -> Bool {
        let links = PastedLinks.parse(text)
        guard links.count >= 2 else { return false }
        let summary = "\(links.count) links pasted"
        pastedText = text
        pastedSummary = summary
        field.stringValue = summary
        field.currentEditor()?.selectedRange = NSRange(location: (summary as NSString).length, length: 0)
        searchSuggestionFetcher.cancel()
        withoutAnimation { model.showLinks(links) }
        iconView.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: nil)
        return true
    }

    private func localServersChanged() {
        guard isOpen else { return }
        withoutAnimation { model.setLocalServers(shell.localServers.servers) }
    }

    func controlTextDidChange(_ notification: Notification) {
        shell.localServers.refreshIfStale()
        if let pastedSummary, field.stringValue != pastedSummary {
            pastedText = nil
            self.pastedSummary = nil
        }
        if pastedText == nil, CommandActions.isActionQuery(field.stringValue) {
            searchSuggestionFetcher.cancel()
            withoutAnimation { model.showActions(CommandActions.ranked(CommandActions.actionQuery(of: field.stringValue))) }
            updateIcon()
            return
        }
        let links = PastedLinks.parse(pastedText ?? field.stringValue)
        if links.count >= 2 {
            searchSuggestionFetcher.cancel()
            withoutAnimation { model.showLinks(links) }
            iconView.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: nil)
            return
        }
        let store = shell.store
        withoutAnimation {
            let historyMatches = shell.history.store(forSpace: shell.currentSpace.id).search(field.stringValue, limit: 60)
            model.update(query: field.stringValue, tabs: store.allTabs, playerTab: store.playerTab, selectedTab: store.selectedTab, archived: shell.archive.entries, history: historyMatches)
        }
        updateIcon()
        searchSuggestionFetcher.fetch(model.trimmedQuery) { [weak self] texts, query in
            self?.withoutAnimation { self?.model.setSearchSuggestions(texts, for: query) }
        }
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.fitSuggestions(animated: true) }
        }
    }

    private func fitSuggestions(animated: Bool) {
        guard isOpen else { return }
        suggestionsView.layoutSubtreeIfNeeded()
        let height = suggestionsView.intrinsicContentSize.height
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

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            model.moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)):
            model.moveSelection(by: 1)
        case #selector(NSResponder.insertNewline(_:)):
            let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let suggestion = model.selectedSuggestion {
                activate(suggestion)
            } else if CommandActions.isActionQuery(query) {
                return true
            } else if !query.isEmpty {
                activate(.open(URLInput.interpret(query)))
            } else {
                close(restoringWebFocus: true)
            }
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            guard case .openLinks(let links) = model.selectedSuggestion else { return false }
            close(restoringWebFocus: false)
            shell.openLinks(links, inBackground: false, nested: true)
            shell.focusSelectedWebContent()
        case #selector(NSResponder.cancelOperation(_:)):
            close(restoringWebFocus: true)
        default:
            return false
        }
        return true
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
        layer?.cornerRadius = CommandBarMetrics.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(Self.opacity).cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
