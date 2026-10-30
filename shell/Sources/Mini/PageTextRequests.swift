import AppKit
import CMiniCore
import MiniRules

@MainActor
enum PageTextRequests {
    private static var pending: [UInt64: (String) -> Void] = [:]
    private static var nextRequest: UInt64 = 1

    static func requestTextStyle(of tab: Tab, completion: @escaping (String) -> Void) {
        guard tab.hasBrowser else { return }
        mini_browser_request_text_style(tab.id, register(completion))
    }

    static func requestPageMarkdown(of tab: Tab, completion: @escaping (String) -> Void) {
        guard tab.hasBrowser else { return }
        mini_browser_request_page_markdown(tab.id, register(completion))
    }

    static func received(request: UInt64, text: String) {
        pending.removeValue(forKey: request)?(text)
    }

    private static func register(_ completion: @escaping (String) -> Void) -> UInt64 {
        let request = nextRequest
        nextRequest += 1
        pending[request] = completion
        return request
    }
}

extension ShellController {
    func pageTextReceived(_ identifier: MiniTabId, request: UInt64, text: String) {
        PageTextRequests.received(request: request, text: text)
    }

    func copyTextStyle(from tab: Tab) {
        PageTextRequests.requestTextStyle(of: tab) { [weak self] reply in
            guard let style = try? JSONDecoder().decode(ComputedTextStyle.self, from: Data(reply.utf8)), let block = TextStyle.block(style) else {
                self?.toast.show("Could Not Copy Text Style")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(block, forType: .string)
            self?.toast.show("Text style copied")
        }
    }

    func copyPageAsMarkdown(from tab: Tab) {
        PageTextRequests.requestPageMarkdown(of: tab) { [weak self] markdown in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(markdown, forType: .string)
            self?.toast.show("Page copied as Markdown")
        }
    }
}
