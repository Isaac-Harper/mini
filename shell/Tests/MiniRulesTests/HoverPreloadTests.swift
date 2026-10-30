import Foundation
import Testing
import MiniRules

struct HoverPreloadTests {
    private func domain(_ host: String) -> String? {
        let labels = host.split(separator: ".")
        return labels.count >= 2 ? labels.suffix(2).joined(separator: ".") : nil
    }

    private func preloads(_ target: String, from page: String = "https://vercel.com/") -> Bool {
        HoverPreload.shouldPreload(target, from: page, registrableDomain: domain)
    }

    @Test func sameSiteLinksPreload() {
        #expect(preloads("https://vercel.com/docs"))
        #expect(preloads("https://docs.vercel.com/guide", from: "https://vercel.com/"))
        #expect(preloads("https://vercel.com/blog?page=2"))
        #expect(preloads("http://127.0.0.1:8790/next", from: "http://127.0.0.1:8790/start"))
    }

    @Test func otherSitesSchemesAndSameDocumentsDoNot() {
        #expect(!preloads("https://github.com/"))
        #expect(!preloads("http://vercel.com/docs"))
        #expect(!preloads("mailto:hi@vercel.com"))
        #expect(!preloads("javascript:void(0)"))
        #expect(!preloads("https://vercel.com/#pricing"))
        #expect(!preloads("not a url"))
    }

    @Test func actionLikeLinksNeverPreload() {
        #expect(!preloads("https://vercel.com/logout"))
        #expect(!preloads("https://vercel.com/account/sign-out"))
        #expect(!preloads("https://vercel.com/api/delete-project/42"))
        #expect(!preloads("https://vercel.com/email?unsubscribe=1"))
        #expect(!preloads("https://vercel.com/item?action=archive"))
        #expect(!preloads("https://vercel.com/index.php?do=remove&id=4"))
        #expect(!preloads("https://vercel.com/session?next=signout"))
    }
}
