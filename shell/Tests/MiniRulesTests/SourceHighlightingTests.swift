import Foundation
import Testing
import MiniRules

struct SourceHighlightingTests {
    private func spans(_ tokens: [SourceToken], in source: String) -> [String] {
        let text = source as NSString
        return tokens.map { "\($0.kind):\(text.substring(with: NSRange(location: $0.location, length: $0.length)))" }
    }

    @Test func tagsAttributesAndValues() {
        let source = #"<a href="/x" hidden data-n=3>Go</a>"#
        #expect(spans(SourceHighlighting.tokens(ofHTML: source), in: source)
            == ["tag:<a", "attribute:href", #"value:"/x""#, "attribute:hidden", "attribute:data-n", "value:3", "tag:>", "tag:</a", "tag:>"])
    }

    @Test func commentsDoctypeAndEntities() {
        let source = "<!doctype html><!-- note --><p>a &amp; b &nbsp; & c</p>"
        #expect(spans(SourceHighlighting.tokens(ofHTML: source), in: source)
            == ["doctype:<!doctype html>", "comment:<!-- note -->", "tag:<p", "tag:>", "entity:&amp;", "entity:&nbsp;", "tag:</p", "tag:>"])
    }

    @Test func selfClosingTagsAndStrayAngles() {
        let source = "a < b <br/> c"
        #expect(spans(SourceHighlighting.tokens(ofHTML: source), in: source) == ["tag:<br", "tag:/>"])
    }

    @Test func scriptContentIsTokenizedAsJavaScript() {
        let source = "<script>const a = 'x<y'; // c\nif (a) return 42</script>"
        #expect(spans(SourceHighlighting.tokens(ofHTML: source), in: source)
            == ["tag:<script", "tag:>", "keyword:const", "string:'x<y'", "comment:// c", "keyword:if", "keyword:return", "number:42", "tag:</script", "tag:>"])
    }

    @Test func styleContentIsTokenizedAsCSS() {
        let source = "<style>@media screen { a { color: red; width: 10px } }/* x */</style>"
        #expect(spans(SourceHighlighting.tokens(ofHTML: source), in: source)
            == ["tag:<style", "tag:>", "keyword:@media", "property:color", "property:width", "number:10px", "comment:/* x */", "tag:</style", "tag:>"])
    }

    @Test func stringsHandleEscapesAndStopAtLineEnds() {
        let source = #"var s = "a\"b"; var t = 'open"# + "\nnext"
        #expect(spans(SourceHighlighting.tokens(ofScript: source), in: source) == ["keyword:var", #"string:"a\"b""#, "keyword:var", "string:'open"])
    }

    @Test func unterminatedConstructsRunToTheEnd() {
        let source = "<!-- never closed"
        #expect(spans(SourceHighlighting.tokens(ofHTML: source), in: source) == ["comment:<!-- never closed"])
        let script = "<script>var a = 1"
        #expect(spans(SourceHighlighting.tokens(ofHTML: script), in: script) == ["tag:<script", "tag:>", "keyword:var", "number:1"])
    }

    @Test func offsetsAreUTF16() {
        let source = "<p title=\"\u{1F600}\">\u{1F600}</p>"
        let tokens = SourceHighlighting.tokens(ofHTML: source)
        #expect(spans(tokens, in: source) == ["tag:<p", "attribute:title", "value:\"\u{1F600}\"", "tag:>", "tag:</p", "tag:>"])
    }

    @Test func largeSourcesStayFast() {
        let line = #"<div class="row"><a href="/item">Item &amp; more</a><script>var x = 1;</script></div>"# + "\n"
        let source = String(repeating: line, count: 60_000)
        let start = Date()
        let tokens = SourceHighlighting.tokens(ofHTML: source)
        #expect(tokens.count == 60_000 * 19)
        #expect(Date().timeIntervalSince(start) < 3)
    }
}
