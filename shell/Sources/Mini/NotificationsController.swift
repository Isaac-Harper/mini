import AppKit
import CMiniCore
@preconcurrency import UserNotifications

@MainActor
final class NotificationsController: NSObject, UNUserNotificationCenterDelegate {
    private unowned let shell: ShellController
    private let center = UNUserNotificationCenter.current()
    private var deliveredIdentifiers: [String: String] = [:]
    private var authorizationRequested = false
    private var authorizationDenied = false
    private var loggedDenial = false

    nonisolated private static let tabKey = "tab"
    nonisolated private static let frameKey = "frame"
    nonisolated private static let notificationKey = "notification"
    nonisolated private static let originKey = "origin"

    init(shell: ShellController) {
        self.shell = shell
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.authorizationDenied = !granted }
            }
        }
    }

    func show(tab: MiniTabId, frameIdentifier: String, notification: UInt32, origin: String, title: String, body: String, tag: String, silent: Bool) {
        requestAuthorizationIfNeeded()
        guard !authorizationDenied else {
            if !loggedDenial {
                loggedDenial = true
                NSLog("Mini: macOS notifications are not authorized for Mini; web notifications are not shown")
            }
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = SitePreferences.host(of: origin) ?? origin
        content.body = body
        content.sound = silent ? nil : .default
        content.userInfo = [
            Self.tabKey: String(tab),
            Self.frameKey: frameIdentifier,
            Self.notificationKey: String(notification),
            Self.originKey: origin,
        ]
        if let attachment = faviconAttachment(for: origin) {
            content.attachments = [attachment]
        }
        let identifier = tag.isEmpty ? "\(tab)|\(frameIdentifier)|\(notification)" : "\(origin)|tag|\(tag)"
        deliveredIdentifiers[Self.key(tab: tab, frame: frameIdentifier, notification: notification)] = identifier
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    func close(tab: MiniTabId, frameIdentifier: String, notification: UInt32) {
        guard let identifier = deliveredIdentifiers.removeValue(
            forKey: Self.key(tab: tab, frame: frameIdentifier, notification: notification)
        ) else { return }
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private static func key(tab: MiniTabId, frame: String, notification: UInt32) -> String {
        "\(tab)|\(frame)|\(notification)"
    }

    private func faviconAttachment(for origin: String) -> UNNotificationAttachment? {
        guard let cached = shell.faviconCache.fileURL(forPageAt: origin),
              FileManager.default.fileExists(atPath: cached.path)
        else { return nil }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("mini-notification-\(UUID().uuidString).png")
        guard (try? FileManager.default.copyItem(at: cached, to: copy)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "icon", url: copy)
    }

    private func clicked(tab: MiniTabId, frameIdentifier: String, notification: UInt32, origin: String) {
        NSApp.activate()
        shell.showWindow()
        guard let tabNode = shell.space(containing: tab)?.store.tab(withIdentifier: tab),
              SitePreferences.origin(of: tabNode.url) == SitePreferences.origin(of: origin)
        else { return }
        shell.reveal(tabNode)
        if tabNode.hasBrowser {
            frameIdentifier.withCString { mini_notification_clicked(tab, $0, notification) }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.content.sound == nil ? [.banner, .list] : [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        guard let tabText = userInfo[Self.tabKey] as? String, let tab = MiniTabId(tabText),
              let frame = userInfo[Self.frameKey] as? String,
              let notificationText = userInfo[Self.notificationKey] as? String, let notification = UInt32(notificationText),
              let origin = userInfo[Self.originKey] as? String
        else { return }
        await MainActor.run {
            self.clicked(tab: tab, frameIdentifier: frame, notification: notification, origin: origin)
        }
    }
}
