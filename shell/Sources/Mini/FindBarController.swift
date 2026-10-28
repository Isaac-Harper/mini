import AppKit
import CMiniCore

@MainActor
final class FindBarController: NSObject, NSTextFieldDelegate {
    private unowned let shell: ShellController
    private let glassView = NSGlassEffectView()
    private let field = NSTextField()
    private var searchedTab: Tab?
    private(set) var isOpen = false

    private static let height: CGFloat = 32

    init(shell: ShellController) {
        self.shell = shell
        super.init()
        buildViews()
    }

    var hasKeyboardFocus: Bool {
        guard isOpen, let editor = field.currentEditor() else { return false }
        return shell.window.firstResponder === editor
    }

    private func buildViews() {
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = "Find"
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        field.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            field.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        glassView.cornerRadius = Self.height / 2
        glassView.contentView = content
        glassView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: glassView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: glassView.trailingAnchor),
            content.topAnchor.constraint(equalTo: glassView.topAnchor),
            content.bottomAnchor.constraint(equalTo: glassView.bottomAnchor),
            glassView.widthAnchor.constraint(equalToConstant: 240),
            glassView.heightAnchor.constraint(equalToConstant: Self.height),
        ])
    }

    func open() {
        guard let tab = shell.store.selectedTab, tab.hasBrowser else { return }
        searchedTab = tab
        if !isOpen {
            isOpen = true
            let windowController = shell.windowController!
            let webAreaView = windowController.webAreaView
            if glassView.superview == nil {
                windowController.rootView.addSubview(glassView)
                NSLayoutConstraint.activate([
                    glassView.topAnchor.constraint(equalTo: webAreaView.topAnchor, constant: 12),
                    glassView.trailingAnchor.constraint(equalTo: webAreaView.trailingAnchor, constant: -12),
                ])
            }
            OverlayAnimation.appear(glassView)
        }
        shell.window.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func findAgain(forward: Bool) {
        guard isOpen, !field.stringValue.isEmpty, let searchedTab else {
            open()
            return
        }
        field.stringValue.withCString { mini_browser_find(searchedTab.id, $0, forward, true) }
    }

    func close(restoringWebFocus: Bool) {
        guard isOpen else { return }
        isOpen = false
        OverlayAnimation.disappear(glassView) { [weak self] in
            self?.glassView.removeFromSuperview()
        }
        if let searchedTab, shell.store.tab(withIdentifier: searchedTab.id) === searchedTab {
            mini_browser_stop_finding(searchedTab.id)
        }
        searchedTab = nil
        if restoringWebFocus {
            shell.focusSelectedWebContent()
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let searchedTab else { return }
        let text = field.stringValue
        if text.isEmpty {
            mini_browser_stop_finding(searchedTab.id)
        } else {
            text.withCString { mini_browser_find(searchedTab.id, $0, true, false) }
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            let isShiftHeld = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            findAgain(forward: !isShiftHeld)
        case #selector(NSResponder.cancelOperation(_:)):
            close(restoringWebFocus: true)
        default:
            return false
        }
        return true
    }
}
