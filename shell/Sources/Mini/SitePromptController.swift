import AppKit
import CMiniCore
import SwiftUI

enum SitePrompt {
    case permission(request: UInt64, origin: String, permissions: UInt32)
    case authentication(request: UInt64, host: String, realm: String, isProxy: Bool)

    var identity: String {
        switch self {
        case .permission(let request, _, _): "permission-\(request)"
        case .authentication(let request, _, _, _): "authentication-\(request)"
        }
    }
}

@MainActor
final class SitePromptController {
    private unowned let shell: ShellController
    private let preferences: SitePreferences
    private var promptsByTab: [MiniTabId: [SitePrompt]] = [:]
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var displayedPromptIdentity: String?

    init(shell: ShellController, preferences: SitePreferences, windowController: MainWindowController) {
        self.shell = shell
        self.preferences = preferences
        let webAreaView = windowController.webAreaView
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.isHidden = true
        windowController.rootView.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: webAreaView.topAnchor, constant: 12),
            hostingView.centerXAnchor.constraint(equalTo: webAreaView.centerXAnchor),
        ])
    }

    var hasTextFocus: Bool {
        guard displayedPromptIdentity?.hasPrefix("authentication") == true,
              let responder = shell.window.firstResponder as? NSView
        else { return false }
        return responder.isDescendant(of: hostingView)
    }

    func permissionRequested(tab identifier: MiniTabId, request: UInt64, origin: String, permissions: UInt32) {
        if let granted = preferences.rememberedGrant(origin: origin, permissions: permissions) {
            mini_permission_respond(request, granted)
            return
        }
        guard shell.store.tab(withIdentifier: identifier) != nil else {
            mini_permission_respond(request, 0)
            return
        }
        promptsByTab[identifier, default: []].append(.permission(request: request, origin: origin, permissions: permissions))
        refresh()
    }

    func permissionDismissed(request dismissedRequest: UInt64) {
        for (identifier, prompts) in promptsByTab {
            promptsByTab[identifier] = prompts.filter { prompt in
                if case .permission(let request, _, _) = prompt { return request != dismissedRequest }
                return true
            }
        }
        refresh()
    }

    func authenticationRequested(tab identifier: MiniTabId, request: UInt64, host: String, realm: String, isProxy: Bool) {
        guard shell.store.tab(withIdentifier: identifier) != nil else {
            mini_auth_respond(request, nil, nil)
            return
        }
        promptsByTab[identifier, default: []].append(
            .authentication(request: request, host: host, realm: realm, isProxy: isProxy))
        refresh()
    }

    func discardPrompts(for tabs: [Tab]) {
        for tab in tabs {
            promptsByTab[tab.id] = nil
        }
        refresh()
    }

    func refresh() {
        guard let tab = shell.store.selectedTab, let prompt = promptsByTab[tab.id]?.first else {
            displayedPromptIdentity = nil
            hostingView.isHidden = true
            hostingView.rootView = AnyView(EmptyView())
            return
        }
        guard prompt.identity != displayedPromptIdentity else { return }
        displayedPromptIdentity = prompt.identity
        hostingView.rootView = view(for: prompt, in: tab)
        hostingView.isHidden = false
    }

    private func view(for prompt: SitePrompt, in tab: Tab) -> AnyView {
        switch prompt {
        case .permission(let request, let origin, let permissions):
            let host = SitePreferences.host(of: origin) ?? origin
            return AnyView(
                PermissionPromptView(
                    host: host,
                    favicon: tab.favicon,
                    permissionNames: Self.names(of: permissions)
                ) { [weak self] allowed in
                    self?.answerPermission(tab: tab, request: request, origin: origin, permissions: permissions, allowed: allowed)
                }
                .id(prompt.identity))
        case .authentication(let request, let host, let realm, let isProxy):
            return AnyView(
                AuthenticationPromptView(host: host, realm: realm, isProxy: isProxy, favicon: tab.favicon) { [weak self] credentials in
                    self?.answerAuthentication(tab: tab, request: request, credentials: credentials)
                }
                .id(prompt.identity))
        }
    }

    private func answerPermission(tab: Tab, request: UInt64, origin: String, permissions: UInt32, allowed: Bool) {
        preferences.remember(origin: origin, permissions: permissions, allowed: allowed)
        mini_permission_respond(request, allowed ? permissions : 0)
        removeFrontPrompt(of: tab)
    }

    private func answerAuthentication(tab: Tab, request: UInt64, credentials: (username: String, password: String)?) {
        if let credentials {
            credentials.username.withCString { username in
                credentials.password.withCString { password in
                    mini_auth_respond(request, username, password)
                }
            }
        } else {
            mini_auth_respond(request, nil, nil)
        }
        removeFrontPrompt(of: tab)
    }

    private func removeFrontPrompt(of tab: Tab) {
        if var prompts = promptsByTab[tab.id], !prompts.isEmpty {
            prompts.removeFirst()
            promptsByTab[tab.id] = prompts
        }
        displayedPromptIdentity = nil
        refresh()
        shell.focusSelectedWebContent()
    }

    private static let permissionNames: [(MiniPermission, String)] = [
        (MINI_PERMISSION_CAMERA, "camera"),
        (MINI_PERMISSION_MICROPHONE, "microphone"),
        (MINI_PERMISSION_SCREEN_CAPTURE, "screen"),
        (MINI_PERMISSION_GEOLOCATION, "location"),
        (MINI_PERMISSION_NOTIFICATIONS, "notifications"),
        (MINI_PERMISSION_CLIPBOARD, "clipboard"),
        (MINI_PERMISSION_MIDI, "MIDI devices"),
        (MINI_PERMISSION_STORAGE, "storage"),
        (MINI_PERMISSION_WINDOW_MANAGEMENT, "window management"),
        (MINI_PERMISSION_LOCAL_NETWORK, "local network"),
        (MINI_PERMISSION_OTHER, "other features"),
    ]

    private static func names(of permissions: UInt32) -> String {
        let names = permissionNames
            .filter { permissions & $0.0.rawValue != 0 }
            .map(\.1)
        return ListFormatter.localizedString(byJoining: names.isEmpty ? ["other features"] : names)
    }
}
