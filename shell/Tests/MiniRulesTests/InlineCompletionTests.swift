import Testing
import MiniRules

struct InlineCompletionTests {
    let hosts = ["www.github.com", "gitlab.com", "news.ycombinator.com"]

    @Test func completesTheFirstHostWithTheTypedPrefix() {
        #expect(InlineCompletion.completion(for: "gi", hosts: hosts) == "github.com")
        #expect(InlineCompletion.completion(for: "gitl", hosts: hosts) == "gitlab.com")
        #expect(InlineCompletion.completion(for: "GitH", hosts: hosts) == "github.com")
        #expect(InlineCompletion.completion(for: "www.gi", hosts: hosts) == "www.github.com")
    }

    @Test func doesNotCompleteShortSpacedPathOrActionInput() {
        #expect(InlineCompletion.completion(for: "g", hosts: hosts) == nil)
        #expect(InlineCompletion.completion(for: "gi hub", hosts: hosts) == nil)
        #expect(InlineCompletion.completion(for: "github.com/", hosts: hosts) == nil)
        #expect(InlineCompletion.completion(for: "localhost:3", hosts: ["localhost"]) == nil)
        #expect(InlineCompletion.completion(for: ">gi", hosts: hosts) == nil)
        #expect(InlineCompletion.completion(for: "github.com", hosts: hosts) == nil)
        #expect(InlineCompletion.completion(for: "news", hosts: []) == nil)
    }

    @Test func completesOnlyWhileTypingForward() {
        #expect(InlineCompletion.isTypingForward(previous: "gi", current: "git"))
        #expect(InlineCompletion.isTypingForward(previous: "GI", current: "git"))
        #expect(!InlineCompletion.isTypingForward(previous: "git", current: "gi"))
        #expect(!InlineCompletion.isTypingForward(previous: "git", current: "git"))
        #expect(!InlineCompletion.isTypingForward(previous: "git", current: "xgit"))
    }

    @Test func completedTextKeepsTheTypedCase() {
        #expect(InlineCompletion.completedText(typed: "GiT", completion: "github.com") == "GiThub.com")
    }
}
