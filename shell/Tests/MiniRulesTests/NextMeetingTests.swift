import Foundation
import Testing
import MiniRules

struct NextMeetingTests {
    private let now = try! Date("2026-01-05T10:00:00Z", strategy: .iso8601)

    private func event(_ title: String, startsIn startMinutes: Double, lasts minutes: Double = 30, isAllDay: Bool = false, isDeclined: Bool = false) -> MeetingEvent {
        let start = now.addingTimeInterval(startMinutes * 60)
        return MeetingEvent(identifier: title, title: title, calendarIdentifier: "work", calendarTitle: "Work", start: start,
                            end: start.addingTimeInterval(minutes * 60), isAllDay: isAllDay, isDeclined: isDeclined, conferenceLink: nil)
    }

    @Test func picksTheEarliestUpcomingMeetingInsideTheHour() {
        let events = [event("Later", startsIn: 40), event("Sooner", startsIn: 10), event("Tomorrow", startsIn: 61)]
        #expect(NextMeeting.select(events, now: now)?.title == "Sooner")
        #expect(NextMeeting.select([event("Edge", startsIn: 60)], now: now)?.title == "Edge")
        #expect(NextMeeting.select([event("Tomorrow", startsIn: 61)], now: now) == nil)
        #expect(NextMeeting.select([], now: now) == nil)
    }

    @Test func ongoingBeatsUpcoming() {
        let events = [event("Soon", startsIn: 2), event("Running", startsIn: -20, lasts: 30), event("Started", startsIn: -5, lasts: 60)]
        #expect(NextMeeting.select(events, now: now)?.title == "Running")
    }

    @Test func skipsDeclinedAllDayAndEndedEvents() {
        let events = [
            event("Declined", startsIn: 5, isDeclined: true),
            event("Holiday", startsIn: -600, lasts: 1440, isAllDay: true),
            event("Over", startsIn: -30, lasts: 30),
            event("Kept", startsIn: 50),
        ]
        #expect(NextMeeting.select(events, now: now)?.title == "Kept")
    }

    @Test func tiesBreakByEarlierEnd() {
        let events = [event("Long", startsIn: 10, lasts: 60), event("Short", startsIn: 10, lasts: 15)]
        #expect(NextMeeting.select(events, now: now)?.title == "Short")
    }

    @Test func nextChangeIsTheNearestWindowStartOrEnd() {
        #expect(NextMeeting.nextChange([event("Far", startsIn: 90)], now: now) == now.addingTimeInterval(30 * 60))
        #expect(NextMeeting.nextChange([event("Soon", startsIn: 10)], now: now) == now.addingTimeInterval(10 * 60))
        #expect(NextMeeting.nextChange([event("Running", startsIn: -10, lasts: 25)], now: now) == now.addingTimeInterval(15 * 60))
        #expect(NextMeeting.nextChange([event("Declined", startsIn: 10, isDeclined: true)], now: now) == nil)
        #expect(NextMeeting.nextChange([], now: now) == nil)
    }

    @Test func relativeTimeText() {
        let meeting = event("Standup", startsIn: 0, lasts: 30)
        #expect(NextMeeting.timeText(for: meeting, now: now.addingTimeInterval(-4 * 60)) == "in 4 min")
        #expect(NextMeeting.timeText(for: meeting, now: now.addingTimeInterval(-4 * 60 - 1)) == "in 5 min")
        #expect(NextMeeting.timeText(for: meeting, now: now.addingTimeInterval(-10)) == "in 1 min")
        #expect(NextMeeting.timeText(for: meeting, now: now.addingTimeInterval(-60 * 60)) == "in 1 h")
        #expect(NextMeeting.timeText(for: meeting, now: now) == "now")
        #expect(NextMeeting.timeText(for: meeting, now: now.addingTimeInterval(4 * 60 + 59)) == "now")
        #expect(NextMeeting.timeText(for: meeting, now: now.addingTimeInterval(18 * 60)) == "ends in 12 min")
        #expect(NextMeeting.timeText(for: meeting, now: now.addingTimeInterval(29 * 60 + 30)) == "ends in 1 min")
        let workshop = event("Workshop", startsIn: 0, lasts: 150)
        #expect(NextMeeting.timeText(for: workshop, now: now.addingTimeInterval(10 * 60)) == "ends in 2 h 20 min")
        #expect(NextMeeting.timeText(for: workshop, now: now.addingTimeInterval(30 * 60)) == "ends in 2 h")
    }

    @Test func emphasisStartsFiveMinutesBefore() {
        let meeting = event("Standup", startsIn: 0, lasts: 30)
        #expect(!NextMeeting.isEmphasized(meeting, now: now.addingTimeInterval(-6 * 60)))
        #expect(NextMeeting.isEmphasized(meeting, now: now.addingTimeInterval(-5 * 60)))
        #expect(NextMeeting.isEmphasized(meeting, now: now.addingTimeInterval(20 * 60)))
        #expect(!NextMeeting.isEmphasized(meeting, now: now.addingTimeInterval(30 * 60)))
    }

    private func link(url: String? = nil, location: String? = nil, notes: String? = nil) -> String? {
        NextMeeting.conferenceLink(url: url, location: location, notes: notes)?.absoluteString
    }

    @Test func findsGoogleMeetInGoogleDescriptions() {
        let notes = """
        Weekly sync

        -::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-
        Join with Google Meet: https://meet.google.com/abc-defg-hij
        Or dial: (US) +1 650-555-0100 PIN: 123456789#
        More phone numbers: https://tel.meet/abc-defg-hij?pin=1234567890

        Learn more about Meet at: https://support.google.com/a/users/answer/9282720
        -::~:~::~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~:~::~:~::-
        """
        #expect(link(notes: notes) == "https://meet.google.com/abc-defg-hij")
        #expect(link(notes: #"<a href="https://meet.google.com/xyz-abcd-efg?authuser=0">Join</a>"#) == "https://meet.google.com/xyz-abcd-efg?authuser=0")
        #expect(link(location: "meet.google.com/abc-defg-hij") == "https://meet.google.com/abc-defg-hij")
        #expect(link(notes: "Docs at https://meet.google.com/ and https://support.google.com/meet") == nil)
        #expect(link(notes: "https://www.google.com/url?q=https://meet.google.com/abc-defg-hij&sa=D&source=calendar") == "https://meet.google.com/abc-defg-hij")
    }

    @Test func findsZoomWithPasswords() {
        let notes = """
        Hi there,

        Example Co is inviting you to a scheduled Zoom meeting.

        Join Zoom Meeting
        https://us02web.zoom.us/j/81234567890?pwd=aBcDeFgHiJkLmNoPqRsTuVwXyZ.1

        Meeting ID: 812 3456 7890
        Passcode: 482913

        One tap mobile
        +16699006833,,81234567890#,,,,*482913# US (San Jose)
        """
        #expect(link(notes: notes) == "https://us02web.zoom.us/j/81234567890?pwd=aBcDeFgHiJkLmNoPqRsTuVwXyZ.1")
        #expect(link(location: "https://zoom.us/my/jane.doe.") == "https://zoom.us/my/jane.doe")
        #expect(link(location: "Zoom (https://example.zoom.us/j/99887766554?pwd=xyz)") == "https://example.zoom.us/j/99887766554?pwd=xyz")
        #expect(link(notes: "Download Zoom at https://zoom.us/download") == nil)
    }

    @Test func findsTeamsWebexAndAround() {
        let teams = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_NjE4ZTE5ZjQtYzY0Zi00%40thread.v2/0?context=%7b%22Tid%22%3a%2272f988bf%22%7d"
        let teamsNotes = """
        ________________________________________________________________________________
        Microsoft Teams meeting
        Join on your computer, mobile app or room device
        Click here to join the meeting<\(teams)>
        Meeting ID: 254 123 456 789
        Passcode: aB3cD4
        Download Teams<https://www.microsoft.com/en-us/microsoft-teams/download-app> | Join on the web<https://www.microsoft.com/microsoft-teams/join-a-meeting>
        ________________________________________________________________________________
        """
        #expect(link(location: "Microsoft Teams Meeting", notes: teamsNotes) == teams)
        #expect(link(notes: "Join: https://teams.microsoft.com/meet/2541234567?p=aB3cD4") == "https://teams.microsoft.com/meet/2541234567?p=aB3cD4")
        #expect(link(notes: "Join from the meeting link\nhttps://example.webex.com/example/j.php?MTID=m1234567890abcdef") == "https://example.webex.com/example/j.php?MTID=m1234567890abcdef")
        #expect(link(location: "https://meet.around.co/r/design-review") == "https://meet.around.co/r/design-review")
        let safeLink = "https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.zoom.us%2Fj%2F123456789&data=05"
        #expect(link(notes: safeLink) == "https://example.zoom.us/j/123456789")
    }

    @Test func precedenceIsURLThenLocationThenNotes() {
        let meet = "https://meet.google.com/abc-defg-hij"
        let zoom = "https://example.zoom.us/j/123456789"
        #expect(link(url: meet, location: zoom, notes: zoom) == meet)
        #expect(link(url: "https://example.com/agenda", location: zoom, notes: meet) == zoom)
        #expect(link(url: nil, location: "Room 4", notes: "See \(meet) or \(zoom)") == meet)
        #expect(link(url: nil, location: "Room 4", notes: "No link here, write to team@example.com") == nil)
    }
}
