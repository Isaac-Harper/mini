import Foundation
import Testing
import MiniRules

struct LinkPreviewTests {
    @Test func openGraphWinsOverTwitterAndTheTitleTag() {
        let preview = LinkPreview(LinkPreviewTags(baseURL: "https://example.com/post", titleTag: "Post | Example", openGraphTitle: "Post",
                                                  twitterTitle: "Tweet title", twitterDescription: "From twitter", description: "From meta",
                                                  openGraphImage: "https://cdn.example.com/og.png", twitterImage: "https://cdn.example.com/tw.png"))
        #expect(preview.title == "Post")
        #expect(preview.description == "From twitter")
        #expect(preview.imageURL == URL(string: "https://cdn.example.com/og.png"))
    }

    @Test func fallsBackToTwitterThenTheTitleTag() {
        let twitter = LinkPreview(LinkPreviewTags(baseURL: "https://example.com/", titleTag: "Tag", twitterTitle: "Tweet", twitterImage: "/card.jpg"))
        #expect(twitter.title == "Tweet")
        #expect(twitter.imageURL == URL(string: "https://example.com/card.jpg"))
        let plain = LinkPreview(LinkPreviewTags(baseURL: "https://example.com/", titleTag: "  Tag  ", openGraphTitle: "   "))
        #expect(plain.title == "Tag")
        #expect(plain.description == nil)
        #expect(plain.imageURL == nil)
    }

    @Test func resolvesRelativeImagesAgainstTheBase() {
        let base = URL(string: "https://example.com/blog/post/")
        #expect(LinkPreview.resolve("cover.png", against: base) == URL(string: "https://example.com/blog/post/cover.png"))
        #expect(LinkPreview.resolve("../cover.png", against: base) == URL(string: "https://example.com/blog/cover.png"))
        #expect(LinkPreview.resolve("/img/cover.png", against: base) == URL(string: "https://example.com/img/cover.png"))
        #expect(LinkPreview.resolve("//cdn.example.net/a.png", against: base) == URL(string: "https://cdn.example.net/a.png"))
        #expect(LinkPreview.resolve("http://other.example/a.png", against: base) == URL(string: "http://other.example/a.png"))
        #expect(LinkPreview.resolve("data:image/png;base64,AAAA", against: base) == nil)
        #expect(LinkPreview.resolve("javascript:alert(1)", against: base) == nil)
        #expect(LinkPreview.resolve("", against: base) == nil)
    }

    @Test func aTwitterImageIsUsedWhenTheOpenGraphOneCannotBeResolved() {
        let preview = LinkPreview(LinkPreviewTags(baseURL: "https://example.com/", openGraphImage: "data:image/png;base64,AAAA", twitterImage: "t.png"))
        #expect(preview.imageURL == URL(string: "https://example.com/t.png"))
    }

    @Test func aspectsNearTheCommonCardPass() {
        #expect(LinkPreview.aspectWarning(for: CGSize(width: 1200, height: 630)) == nil)
        #expect(LinkPreview.aspectWarning(for: CGSize(width: 1280, height: 720)) == nil)
        #expect(LinkPreview.aspectWarning(for: CGSize(width: 1000, height: 500)) == nil)
        #expect(LinkPreview.aspectWarning(for: CGSize(width: 600, height: 600)) == "Image is 1:1, most apps crop to 1.91:1")
        #expect(LinkPreview.aspectWarning(for: CGSize(width: 800, height: 600)) == "Image is 4:3, most apps crop to 1.91:1")
        #expect(LinkPreview.aspectWarning(for: CGSize(width: 1080, height: 1920)) == "Image is 9:16, most apps crop to 1.91:1")
        #expect(LinkPreview.aspectWarning(for: CGSize(width: 1000, height: 300)) == "Image is 3.33:1, most apps crop to 1.91:1")
        #expect(LinkPreview.aspectWarning(for: CGSize(width: 0, height: 300)) == nil)
    }

    @Test func diagnosticsNameTheFirstProblem() {
        let full = LinkPreview(LinkPreviewTags(baseURL: "https://example.com/", openGraphTitle: "T", openGraphImage: "a.png", declaredImageWidth: 600, declaredImageHeight: 600))
        #expect(full.diagnostic(image: .pending) == "Image is 1:1, most apps crop to 1.91:1")
        #expect(full.diagnostic(image: .loaded(CGSize(width: 1200, height: 630))) == nil)
        #expect(full.diagnostic(image: .failed) == "Preview image did not load")
        let bare = LinkPreview(LinkPreviewTags(baseURL: "https://example.com/"))
        #expect(bare.diagnostic(image: .pending) == "No preview image")
        let untitled = LinkPreview(LinkPreviewTags(baseURL: "https://example.com/", openGraphImage: "a.png"))
        #expect(untitled.diagnostic(image: .loaded(CGSize(width: 1200, height: 630))) == "No title tag")
    }
}
