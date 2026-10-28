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
    private var suggestionsView: OverlayHostingView<CommandSuggestionsView>!
    private let offsetGuide = NSLayoutGuide()
    private let searchSuggestionFetcher = SearchSuggestionFetcher()
    private var mode: CommandBarMode = .newTab
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
        suggestionsView.sizingOptions = [.minSize, .intrinsicContentSize]
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

        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        iconView.contentTintColor = .secondaryLabelColor
        updateIcon()

        let content = NSView()
        for view in [field, iconView, suggestionsView!, content] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        content.addSubview(iconView)
        content.addSubview(field)
        content.addSubview(suggestionsView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            field.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            suggestionsView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            suggestionsView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            suggestionsView.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 12),
            suggestionsView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -4),
        ])

        glassView.cornerRadius = 20
        glassView.style = .regular
        glassView.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.55)
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
        if !isOpen {
            isOpen = true
            attach(to: shell.windowController!)
            OverlayAnimation.appear(glassView)
            dismissView.alphaValue = 1
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
        if !trimmed.isEmpty, case .address = URLInput.interpret(trimmed) {
            symbolName = "globe"
        } else {
            symbolName = "magnifyingglass"
        }
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }

    private func activate(_ suggestion: CommandSuggestion) {
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
        }
        shell.focusSelectedWebContent()
    }

    private func openTypedInputInBackground() {
        let query = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        close(restoringWebFocus: true)
        shell.openInBackground(URLInput.interpret(query).url)
    }

    func controlTextDidChange(_ notification: Notification) {
        let store = shell.store
        withoutAnimation {
            model.update(query: field.stringValue, tabs: store.allTabs, selectedTab: store.selectedTab, archived: shell.archive.entries)
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
            } else if !query.isEmpty {
                activate(.open(URLInput.interpret(query)))
            } else {
                close(restoringWebFocus: true)
            }
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

    private static let returnKeyCodes: Set<UInt16> = [36, 76]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, Self.returnKeyCodes.contains(event.keyCode), currentEditor() != nil {
            onCommandReturn?()
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
