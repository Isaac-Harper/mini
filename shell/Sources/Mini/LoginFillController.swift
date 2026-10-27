import AppKit
import CMiniCore

@MainActor
final class LoginFillController {
    private struct Target: Equatable {
        let tab: MiniTabId
        let frameIdentifier: String
        let origin: String

        var suppressionKey: String { "\(tab)|\(frameIdentifier)|\(origin)" }
    }

    private unowned let shell: ShellController
    private let card = LoginFillCardView()
    private var target: Target?
    private var cancelledAt: [String: Date] = [:]
    private var explicitRequestTabs: Set<MiniTabId> = []

    private static let cancelSuppression: TimeInterval = 30

    init(shell: ShellController) {
        self.shell = shell
        card.onFill = { [weak self] in self?.fill() }
        card.onCancel = { [weak self] in self?.cancel() }
    }

    var isOpen: Bool { target != nil }

    func requestFill(for tab: Tab) {
        guard tab.hasBrowser else { return }
        explicitRequestTabs.insert(tab.id)
        mini_request_login_fill(tab.id)
    }

    func loginFieldFocused(tab identifier: MiniTabId, frameIdentifier: String, origin: String) {
        let isExplicit = explicitRequestTabs.remove(identifier) != nil
        guard target == nil,
              let tab = shell.store.selectedTab, tab.id == identifier,
              !shell.commandBar.isOpen, !shell.findBar.hasKeyboardFocus, !shell.sitePrompts.hasTextFocus
        else { return }
        let candidate = Target(tab: identifier, frameIdentifier: frameIdentifier, origin: origin)
        if !isExplicit, let cancelled = cancelledAt[candidate.suppressionKey],
           Date().timeIntervalSince(cancelled) < Self.cancelSuppression {
            return
        }
        show(candidate, in: tab)
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
        windowController.rootView.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: windowController.webAreaView.topAnchor, constant: 12),
            card.centerXAnchor.constraint(equalTo: windowController.webAreaView.centerXAnchor),
        ])
        windowController.rootView.layoutSubtreeIfNeeded()
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

    private func cancel() {
        guard let target else { return }
        cancelledAt[target.suppressionKey] = Date()
        dismiss(restoringWebFocus: true)
    }

    private func dismiss(restoringWebFocus: Bool) {
        guard target != nil else { return }
        target = nil
        card.clearFields()
        card.removeFromSuperview()
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
