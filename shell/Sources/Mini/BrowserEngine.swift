import AppKit
import CMiniCore

@MainActor
final class BrowserEngine {
    static let shared = BrowserEngine()

    var shell: ShellController?

    fileprivate var requiredShell: ShellController {
        guard let shell else { preconditionFailure("Browser event arrived before the shell was created") }
        return shell
    }

    static var callbacks: MiniCallbacks {
        MiniCallbacks(
            address_changed: { identifier, url in
                let url = requiredString(url)
                MainActor.assumeIsolated { BrowserEngine.shared.requiredShell.addressChanged(identifier, url: url) }
            },
            title_changed: { identifier, title in
                let title = requiredString(title)
                MainActor.assumeIsolated { BrowserEngine.shared.requiredShell.titleChanged(identifier, title: title) }
            },
            favicon_changed: { identifier, png, length in
                let pngData = length > 0 && png != nil ? Data(bytes: png!, count: length) : Data()
                MainActor.assumeIsolated { BrowserEngine.shared.requiredShell.faviconChanged(identifier, pngData: pngData) }
            },
            loading_state_changed: { identifier, isLoading, canGoBack, canGoForward in
                MainActor.assumeIsolated {
                    BrowserEngine.shared.requiredShell.loadingStateChanged(
                        identifier, isLoading: isLoading, canGoBack: canGoBack, canGoForward: canGoForward)
                }
            },
            open_tab_requested: { opener, url, foreground in
                let url = requiredString(url)
                MainActor.assumeIsolated {
                    BrowserEngine.shared.requiredShell.openTabRequested(opener, url: url, foreground: foreground)
                }
            },
            popup_requested: { opener, url in
                let url = requiredString(url)
                let (tab, hostViewAddress) = MainActor.assumeIsolated {
                    let target = BrowserEngine.shared.requiredShell.popupRequested(opener, url: url)
                    let address = target.hostView.map { UInt(bitPattern: Unmanaged.passUnretained($0).toOpaque()) } ?? 0
                    return (target.tab, address)
                }
                return MiniPopupTarget(tab: tab, parent_view: UnsafeMutableRawPointer(bitPattern: hostViewAddress))
            },
            pre_key_event: { identifier, eventPointer in
                guard let eventPointer else { preconditionFailure("pre_key_event without an NSEvent") }
                let eventAddress = UInt(bitPattern: eventPointer)
                return MainActor.assumeIsolated {
                    guard let pointer = UnsafeRawPointer(bitPattern: eventAddress) else {
                        preconditionFailure("pre_key_event pointer round trip failed")
                    }
                    let event = Unmanaged<NSEvent>.fromOpaque(pointer).takeUnretainedValue()
                    if let redo = MenuKeyEquivalents.undoDirection(of: event) {
                        return BrowserEngine.shared.requiredShell.pageUndoKeyPressed(in: identifier, redo: redo)
                    }
                    return MenuKeyEquivalents.perform(event)
                }
            },
            focus_requested: { identifier in
                MainActor.assumeIsolated { BrowserEngine.shared.requiredShell.focusRequested(identifier) }
            },
            web_got_focus: { identifier in
                MainActor.assumeIsolated { BrowserEngine.shared.requiredShell.webGotFocus(identifier) }
            },
            download_updated: { download, fileName, path, receivedBytes, totalBytes, isComplete, isCanceled in
                let progress = DownloadProgress(
                    id: download,
                    fileName: requiredString(fileName),
                    path: requiredString(path),
                    receivedBytes: receivedBytes,
                    totalBytes: totalBytes,
                    isComplete: isComplete,
                    isCanceled: isCanceled
                )
                MainActor.assumeIsolated { BrowserEngine.shared.requiredShell.downloadUpdated(progress) }
            },
            permission_requested: { identifier, request, origin, permissions in
                let origin = requiredString(origin)
                MainActor.assumeIsolated {
                    BrowserEngine.shared.requiredShell.permissionRequested(
                        identifier, request: request, origin: origin, permissions: permissions)
                }
            },
            permission_dismissed: { request in
                MainActor.assumeIsolated { BrowserEngine.shared.requiredShell.permissionDismissed(request: request) }
            },
            auth_requested: { identifier, request, host, realm, isProxy in
                let host = requiredString(host)
                let realm = realm.map { String(cString: $0) } ?? ""
                MainActor.assumeIsolated {
                    BrowserEngine.shared.requiredShell.authenticationRequested(
                        identifier, request: request, host: host, realm: realm, isProxy: isProxy)
                }
            },
            login_field_focused: { identifier, frameIdentifier, origin in
                let frameIdentifier = requiredString(frameIdentifier)
                let origin = requiredString(origin)
                MainActor.assumeIsolated {
                    BrowserEngine.shared.requiredShell.loginFieldFocused(
                        identifier, frameIdentifier: frameIdentifier, origin: origin)
                }
            },
            render_process_terminated: { identifier, reason in
                MainActor.assumeIsolated {
                    BrowserEngine.shared.requiredShell.renderProcessTerminated(identifier, reason: reason)
                }
            },
            login_form_presence_changed: { identifier, hasLoginForm in
                MainActor.assumeIsolated {
                    BrowserEngine.shared.requiredShell.loginFormPresenceChanged(identifier, hasLoginForm: hasLoginForm)
                }
            },
            notification_show: { identifier, frame, notification, origin, title, body, tag, silent in
                let frame = requiredString(frame)
                let origin = requiredString(origin)
                let title = requiredString(title)
                let body = requiredString(body)
                let tag = requiredString(tag)
                MainActor.assumeIsolated {
                    BrowserEngine.shared.requiredShell.notificationShow(
                        identifier, frame: frame, notification: notification, origin: origin,
                        title: title, body: body, tag: tag, silent: silent)
                }
            },
            notification_close: { identifier, frame, notification in
                let frame = requiredString(frame)
                MainActor.assumeIsolated {
                    BrowserEngine.shared.requiredShell.notificationClose(identifier, frame: frame, notification: notification)
                }
            },
            audio_state_changed: { identifier, isPlaying, mediaTitle in
                let mediaTitle = requiredString(mediaTitle)
                MainActor.assumeIsolated {
                    BrowserEngine.shared.requiredShell.audioStateChanged(identifier, isPlaying: isPlaying, mediaTitle: mediaTitle)
                }
            },
            status_message_changed: { identifier, text in
                let text = requiredString(text)
                MainActor.assumeIsolated { BrowserEngine.shared.requiredShell.statusMessageChanged(identifier, text: text) }
            },
            fullscreen_mode_changed: { identifier, fullscreen in
                MainActor.assumeIsolated { BrowserEngine.shared.requiredShell.fullscreenModeChanged(identifier, fullscreen: fullscreen) }
            },
            loading_progress_changed: { identifier, progress in
                MainActor.assumeIsolated { BrowserEngine.shared.requiredShell.loadingProgressChanged(identifier, progress: progress) }
            },
            theme_color_changed: { identifier, rgba in
                MainActor.assumeIsolated { BrowserEngine.shared.requiredShell.themeColorChanged(identifier, rgba: rgba) }
            },
            horizontal_scroll_reported: { identifier, canScrollLeft, canScrollRight in
                MainActor.assumeIsolated {
                    BrowserEngine.shared.requiredShell.horizontalScrollReported(identifier, room: HorizontalScrollRoom(canScrollLeft: canScrollLeft, canScrollRight: canScrollRight))
                }
            },
            context_menu_requested: { identifier, menu in
                guard let menu else { preconditionFailure("context_menu_requested without a menu") }
                let request = PageContextRequest(menu.pointee)
                MainActor.assumeIsolated { BrowserEngine.shared.requiredShell.contextMenuRequested(identifier, request: request) }
            },
            image_copied: { identifier, png, length in
                let pngData = length > 0 && png != nil ? Data(bytes: png!, count: length) : Data()
                MainActor.assumeIsolated { BrowserEngine.shared.requiredShell.imageCopied(identifier, pngData: pngData) }
            },
            browser_closed: { identifier in
                MainActor.assumeIsolated { BrowserEngine.shared.requiredShell.browserClosed(identifier) }
            },
            all_browsers_closed: {
                MainActor.assumeIsolated {
                    if BrowserEngine.shared.requiredShell.isTerminating {
                        mini_quit_message_loop()
                    }
                }
            },
            app_relaunched: { arguments, count in
                let arguments = (0..<count).map { index in requiredString(arguments?[index]) }
                MainActor.assumeIsolated { BrowserEngine.shared.requiredShell.appRelaunched(arguments: arguments) }
            }
        )
    }
}

private func requiredString(_ pointer: UnsafePointer<CChar>?) -> String {
    guard let pointer else { preconditionFailure("Core passed a null string") }
    return String(cString: pointer)
}
