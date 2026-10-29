import Testing
import MiniRules

struct UnreadTitleTests {
    @Test func leadingParenthesizedCount() {
        #expect(UnreadTitle.parse("(3) Inbox") == UnreadTitle(count: 3, title: "Inbox"))
        #expect(UnreadTitle.parse("(120) Feed | Site") == UnreadTitle(count: 120, title: "Feed | Site"))
    }

    @Test func trailingParenthesizedCount() {
        #expect(UnreadTitle.parse("Inbox (3)") == UnreadTitle(count: 3, title: "Inbox"))
    }

    @Test func leadingBracketedCount() {
        #expect(UnreadTitle.parse("[3] Chat") == UnreadTitle(count: 3, title: "Chat"))
    }

    @Test func unreadWording() {
        #expect(UnreadTitle.parse("3 unread") == UnreadTitle(count: 3, title: ""))
        #expect(UnreadTitle.parse("12 unread messages - Team") == UnreadTitle(count: 12, title: "Team"))
        #expect(UnreadTitle.parse("2 Unread \u{00B7} Chat") == UnreadTitle(count: 2, title: "Chat"))
        #expect(UnreadTitle.parse("3 unreadable things") == nil)
    }

    @Test func dotPrefixesMeanUnreadWithoutCount() {
        #expect(UnreadTitle.parse("\u{2022} Discord | General") == UnreadTitle(count: nil, title: "Discord | General"))
        #expect(UnreadTitle.parse("* Slack | general") == UnreadTitle(count: nil, title: "Slack | general"))
        #expect(UnreadTitle.parse("*Untitled") == nil)
    }

    @Test func zeroCountStripsWithoutBadge() {
        let parsed = UnreadTitle.parse("(0) Inbox")
        #expect(parsed == UnreadTitle(count: 0, title: "Inbox"))
        #expect(parsed?.showsBadge == false)
        #expect(UnreadTitle(count: nil, title: "x").showsBadge)
    }

    @Test func falsePositivesAreIgnored() {
        #expect(UnreadTitle.parse("Top 10 (2024)") == nil)
        #expect(UnreadTitle.parse("Chapter (3) of a book") == nil)
        #expect(UnreadTitle.parse("Release 1.2.3") == nil)
        #expect(UnreadTitle.parse("(1.2) Notes") == nil)
        #expect(UnreadTitle.parse("Python 3.12 (64-bit)") == nil)
        #expect(UnreadTitle.parse("iOS 18 (22A3354)") == nil)
        #expect(UnreadTitle.parse("2 Fast 2 Furious") == nil)
        #expect(UnreadTitle.parse("(3)") == nil)
        #expect(UnreadTitle.parse("Plain title") == nil)
    }

    @Test func countBeforeSeparatorOnlyWhenAllowed() {
        #expect(UnreadTitle.parse("Inbox (3) - me@example.com - Gmail") == nil)
        #expect(UnreadTitle.parse("Inbox (3) - me@example.com - Gmail", allowsCountBeforeSeparator: true) == UnreadTitle(count: 3, title: "Inbox - me@example.com - Gmail"))
        #expect(UnreadTitle.parse("Archive (2019) - Gmail", allowsCountBeforeSeparator: true) == nil)
    }

    @Test func badgeLabelCapsAt99() {
        #expect(UnreadTitle.badgeLabel(count: 7) == "7")
        #expect(UnreadTitle.badgeLabel(count: 99) == "99")
        #expect(UnreadTitle.badgeLabel(count: 100) == "99+")
    }

    @Test func messagingSites() {
        #expect(UnreadTitle.isMessagingSite(host: "mail.google.com", path: "/mail/u/0/"))
        #expect(UnreadTitle.isMessagingSite(host: "outlook.office.com", path: "/mail/"))
        #expect(UnreadTitle.isMessagingSite(host: "acme.slack.com", path: "/"))
        #expect(UnreadTitle.isMessagingSite(host: "app.slack.com", path: "/client"))
        #expect(UnreadTitle.isMessagingSite(host: "discord.com", path: "/channels/1"))
        #expect(UnreadTitle.isMessagingSite(host: "messages.google.com", path: "/web"))
        #expect(UnreadTitle.isMessagingSite(host: "linear.app", path: "/team/inbox"))
        #expect(UnreadTitle.isMessagingSite(host: "github.com", path: "/notifications"))
        #expect(!UnreadTitle.isMessagingSite(host: "github.com", path: "/apple/swift"))
        #expect(!UnreadTitle.isMessagingSite(host: "google.com", path: "/"))
        #expect(!UnreadTitle.isMessagingSite(host: "notslack.com", path: "/"))
    }
}

struct UnreadBadgeTrackerTests {
    @Test func messagingSiteBadgesAtOnce() {
        var tracker = UnreadBadgeTracker()
        #expect(tracker.update(title: "Inbox (3) - me@example.com - Gmail", host: "mail.google.com", path: "/mail/u/0/") == UnreadTitle(count: 3, title: "Inbox - me@example.com - Gmail"))
    }

    @Test func otherSitesNeedTheCountToChange() {
        var tracker = UnreadBadgeTracker()
        #expect(tracker.update(title: "(3) Feed", host: "example.com", path: "/") == nil)
        #expect(tracker.update(title: "(3) Feed", host: "example.com", path: "/") == nil)
        #expect(tracker.update(title: "(4) Feed", host: "example.com", path: "/") == UnreadTitle(count: 4, title: "Feed"))
        #expect(tracker.update(title: "Other page", host: "example.com", path: "/other") == nil)
        #expect(tracker.update(title: "(1) Feed", host: "example.com", path: "/") == UnreadTitle(count: 1, title: "Feed"))
    }

    @Test func countAppearingOnTheSameTitleCounts() {
        var tracker = UnreadBadgeTracker()
        #expect(tracker.update(title: "Chat", host: "chat.example", path: "/") == nil)
        #expect(tracker.update(title: "\u{2022} Chat", host: "chat.example", path: "/") == UnreadTitle(count: nil, title: "Chat"))
    }

    @Test func differentPagesWithNumbersDoNotConfirm() {
        var tracker = UnreadBadgeTracker()
        #expect(tracker.update(title: "Top 10 (2024)", host: "blog.example", path: "/a") == nil)
        #expect(tracker.update(title: "Part (2)", host: "blog.example", path: "/b") == nil)
        #expect(tracker.update(title: "Other (3)", host: "blog.example", path: "/c") == nil)
    }

    @Test func changingSiteForgetsConfirmation() {
        var tracker = UnreadBadgeTracker()
        _ = tracker.update(title: "(1) Feed", host: "example.com", path: "/")
        #expect(tracker.update(title: "(2) Feed", host: "example.com", path: "/") != nil)
        #expect(tracker.update(title: "(2) Feed", host: "other.example", path: "/") == nil)
    }
}
