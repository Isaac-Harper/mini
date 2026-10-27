import AppKit
import SwiftUI

@MainActor
final class CommandBarController: NSObject, NSTextFieldDelegate {
    private unowned let shell: ShellController
    private let model = CommandBarModel()
    private let dismissView = OverlayDismissView()
    private let glassView = NSGlassEffectView()
    private let field = NSTextField()
    private var suggestionsView: OverlayHostingView<CommandSuggestionsView>!
    private let offsetGuide = NSLayoutGuide()
    private var mode: CommandBarMode = .newTab
    private(set) var isOpen = false

    private static let width: CGFloat = 560

    init(shell: ShellController) {
        self.shell = shell
        super.init()
        suggestionsView = OverlayHostingView(rootView: CommandSuggestionsView(model: model) { [weak self] suggestion in
            self?.activate(suggestion)
        })
        buildViews()
    }

    private func buildViews() {
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 17)
        field.placeholderString = "Search or enter URL"
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self

        let content = NSView()
        for view in [field, suggestionsView!, content] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        content.addSubview(field)
        content.addSubview(suggestionsView)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            field.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            suggestionsView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6),
            suggestionsView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            suggestionsView.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
            suggestionsView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -6),
        ])

        glassView.cornerRadius = 16
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
        let windowController = shell.windowController!
        if !isOpen {
            isOpen = true
            attach(to: windowController)
        }
        let currentURL = shell.store.selectedTab?.url ?? ""
        field.stringValue = mode == .editCurrent ? currentURL : ""
        model.update(query: "", tabs: [], selectedTab: nil)
        shell.window.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func close(restoringWebFocus: Bool) {
        guard isOpen else { return }
        isOpen = false
        dismissView.removeFromSuperview()
        if restoringWebFocus {
            shell.focusSelectedWebContent()
        }
    }

    private func attach(to windowController: MainWindowController) {
        let rootView = windowController.rootView
        let webAreaView = windowController.webAreaView
        rootView.addSubview(dismissView)
        if offsetGuide.owningView == nil {
            rootView.addLayoutGuide(offsetGuide)
            NSLayoutConstraint.activate([
                offsetGuide.topAnchor.constraint(equalTo: webAreaView.topAnchor),
                offsetGuide.heightAnchor.constraint(equalTo: webAreaView.heightAnchor, multiplier: 0.18),
            ])
        }
        NSLayoutConstraint.activate([
            dismissView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            dismissView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            dismissView.topAnchor.constraint(equalTo: rootView.topAnchor),
            dismissView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            glassView.topAnchor.constraint(equalTo: offsetGuide.bottomAnchor),
            glassView.centerXAnchor.constraint(equalTo: webAreaView.centerXAnchor),
            glassView.widthAnchor.constraint(equalToConstant: Self.width).withPriority(.defaultHigh),
            glassView.widthAnchor.constraint(lessThanOrEqualTo: webAreaView.widthAnchor, constant: -32),
        ])
    }

    private func activate(_ suggestion: CommandSuggestion) {
        let mode = self.mode
        close(restoringWebFocus: false)
        switch suggestion {
        case .switchToTab(let tab):
            shell.store.select(tab)
        case .open(let interpretation):
            shell.open(interpretation.url, from: mode)
        }
        shell.focusSelectedWebContent()
    }

    func controlTextDidChange(_ notification: Notification) {
        let store = shell.store
        model.update(query: field.stringValue, tabs: store.allTabs, selectedTab: store.selectedTab)
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
