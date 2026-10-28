import AppKit
import CMiniCore

@MainActor
final class LoginFillController {
    private struct Target: Equatable {
        let tab: MiniTabId
        let frameIdentifier: String
        let origin: String
    }

    private unowned let shell: ShellController
    private let card = LoginFillCardView()
    private var target: Target?

    init(shell: ShellController) {
        self.shell = shell
        card.onFill = { [weak self] in self?.fill() }
        card.onCancel = { [weak self] in self?.dismiss(restoringWebFocus: true) }
    }

    var isOpen: Bool { target != nil }

    func requestFill(for tab: Tab) {
        guard tab.hasBrowser else { return }
        mini_request_login_fill(tab.id)
    }

    func loginFieldFocused(tab identifier: MiniTabId, frameIdentifier: String, origin: String) {
        guard target == nil,
              let tab = shell.store.selectedTab, tab.id == identifier,
              !shell.commandBar.isOpen, !shell.findBar.hasKeyboardFocus, !shell.sitePrompts.hasTextFocus
        else { return }
        show(Target(tab: identifier, frameIdentifier: frameIdentifier, origin: origin), in: tab)
    }

    func close(forTab identifier: MiniTabId) {
        guard target?.tab == identifier else { return }
        dismiss(restoringWebFocus: false)
    }

    func closeIfFieldsLostFocus() {
        guard isOpen else { return }
        if let responder = shell.window.firstResponder as? NSView, responder.isDescendant(of: card) { return }
        dismiss(restoringWebFocus: false)
    }

    func closeIfOpen() {
        dismiss(restoringWebFocus: false)
    }

    private func show(_ newTarget: Target, in tab: Tab) {
        let originHost = SitePreferences.host(of: newTarget.origin) ?? newTarget.origin
        let tabHost = SitePreferences.host(of: tab.url)
        let embeddingHost = tabHost.flatMap { Self.registrableHost($0) == Self.registrableHost(originHost) ? nil : $0 }
        card.clearFields()
        card.configure(host: originHost, embeddingHost: embeddingHost)
        target = newTarget
        let windowController = shell.windowController!
        if card.superview == nil {
            windowController.rootView.addSubview(card)
            NSLayoutConstraint.activate([
                card.topAnchor.constraint(equalTo: windowController.webAreaView.topAnchor, constant: 12),
                card.centerXAnchor.constraint(equalTo: windowController.webAreaView.centerXAnchor),
            ])
        }
        windowController.rootView.layoutSubtreeIfNeeded()
        OverlayAnimation.appear(card)
        shell.window.makeFirstResponder(card.passwordField)
    }

    private func fill() {
        guard let target else { return }
        let username = card.usernameField.stringValue
        let password = card.passwordField.stringValue
        target.frameIdentifier.withCString { frameIdentifier in
            target.origin.withCString { origin in
                username.withCString { username in
                    password.withCString { password in
                        mini_fill_login(target.tab, frameIdentifier, origin, username, password)
                    }
                }
            }
        }
        dismiss(restoringWebFocus: true)
    }

    private func dismiss(restoringWebFocus: Bool) {
        guard target != nil else { return }
        target = nil
        card.clearFields()
        OverlayAnimation.disappear(card) { [weak self] in
            self?.card.removeFromSuperview()
        }
        if restoringWebFocus {
            shell.focusSelectedWebContent()
        }
    }

    private static func registrableHost(_ host: String) -> String {
        let labels = host.split(separator: ".")
        guard labels.count > 2 else { return host }
        return labels.suffix(2).joined(separator: ".")
    }
}
