import AppKit

@MainActor
enum DefaultBrowser {
    static var isDefault: Bool {
        guard let probe = URL(string: "https://example.com"),
              let handler = NSWorkspace.shared.urlForApplication(toOpen: probe)
        else { return false }
        return handler.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    static func makeDefault() {
        let applicationURL = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: applicationURL, toOpenURLsWithScheme: "http") { error in
            if let error {
                NSLog("Mini: could not become the default http handler: %@", String(describing: error))
                return
            }
            Task { @MainActor in
                NSWorkspace.shared.setDefaultApplication(at: applicationURL, toOpenURLsWithScheme: "https") { error in
                    if let error {
                        NSLog("Mini: could not become the default https handler: %@", String(describing: error))
                    }
                }
            }
        }
    }
}
