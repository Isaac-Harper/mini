import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let supportDirectory: URL = {
        guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("No Application Support directory")
        }
        return applicationSupport.appendingPathComponent("Mini")
    }()

    private var shell: ShellController?
    private var urlsOpenedBeforeLaunch: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        let shell = ShellController(
            sessionStore: SessionStore(directory: Self.supportDirectory),
            sitePreferences: SitePreferences(directory: Self.supportDirectory)
        )
        self.shell = shell
        BrowserEngine.shared.shell = shell
        NSApp.mainMenu = MainMenu.make(commands: shell)
        shell.launch(openingURLs: urlsOpenedBeforeLaunch)
        urlsOpenedBeforeLaunch = []
        NSApp.activate()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let shell else {
            urlsOpenedBeforeLaunch.append(contentsOf: urls)
            return
        }
        for url in urls {
            shell.openExternalURL(url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        shell?.showWindow()
        return false
    }
}
