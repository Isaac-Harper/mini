import Foundation
import Testing
import MiniRules

struct HarvestSlotTests {
    private func entry(_ id: UInt64, hours: Double, startedAt: String? = nil, updatedAt: String = "", project: String = "Website", task: String = "Design", notes: String = "") -> HarvestEntry {
        HarvestEntry(id: id, project: project, client: "Example Co", task: task, notes: notes, hours: hours, timerStartedAt: startedAt, updatedAt: updatedAt)
    }

    private let fetchedAt = try! Date("2026-01-05T10:30:00Z", strategy: .iso8601)

    @Test func parsesThePageReport() throws {
        let report = #"{"fetchedAt":1767609000000,"signedIn":true,"entries":[{"id":7,"project":"Website","client":"Example Co","task":"Design","notes":"Header","hours":1.5,"timerStartedAt":"2026-01-05T10:00:00Z","updatedAt":"2026-01-05T10:00:00Z"}]}"#
        let timesheet = try #require(HarvestTimesheet.parse(report))
        #expect(timesheet.signedIn)
        #expect(timesheet.fetchDate == fetchedAt)
        #expect(timesheet.entries == [entry(7, hours: 1.5, startedAt: "2026-01-05T10:00:00Z", updatedAt: "2026-01-05T10:00:00Z", notes: "Header")])
        #expect(HarvestTimesheet.parse(#"{"signedIn":true,"entries":[]}"#) == nil)
        #expect(HarvestTimesheet.parse("not json") == nil)
    }

    @Test func runningTimerKeepsTheTimeBeforeItStarted() throws {
        let timesheet = HarvestTimesheet(fetchedAt: fetchedAt.timeIntervalSince1970 * 1000, signedIn: true, entries: [
            entry(1, hours: 2, updatedAt: "2026-01-05T09:00:00Z"),
            entry(2, hours: 1.5, startedAt: "2026-01-05T10:00:00Z"),
        ])
        guard case .running(let timer) = HarvestSlot.presentation(url: "https://example.harvestapp.com/time", timesheet: timesheet) else {
            Issue.record("expected a running timer")
            return
        }
        #expect(timer.entry.id == 2)
        #expect(timer.priorSeconds == 3600)
        #expect(timer.elapsedSeconds(at: fetchedAt.addingTimeInterval(65)) == 3600 + 1800 + 65)
        #expect(timer.elapsedSeconds(at: timer.startedAt.addingTimeInterval(-10)) == 3600)
    }

    @Test func stoppedShowsTodayAndTheLastTouchedEntry() {
        let timesheet = HarvestTimesheet(fetchedAt: 0, signedIn: true, entries: [
            entry(1, hours: 2, updatedAt: "2026-01-05T11:00:00Z"),
            entry(2, hours: 1.25, updatedAt: "2026-01-05T09:00:00Z"),
        ])
        #expect(HarvestSlot.presentation(url: "https://example.harvestapp.com/time/day/2026/1/5", timesheet: timesheet)
            == .stopped(todaySeconds: 3.25 * 3600, last: timesheet.entries[0]))
        let empty = HarvestTimesheet(fetchedAt: 0, signedIn: true, entries: [])
        #expect(HarvestSlot.presentation(url: "https://example.harvestapp.com/time", timesheet: empty) == .stopped(todaySeconds: 0, last: nil))
    }

    @Test func signInPagesAndSignedOutReportsAskToSignIn() {
        let signedOut = HarvestTimesheet(fetchedAt: 0, signedIn: false, entries: [])
        #expect(HarvestSlot.presentation(url: "https://example.harvestapp.com/time", timesheet: signedOut) == .signedOut)
        #expect(HarvestSlot.presentation(url: "https://id.getharvest.com/sessions/new", timesheet: nil) == .signedOut)
        #expect(HarvestSlot.presentation(url: "https://harvestapp.com/time", timesheet: nil) == .idle)
        #expect(HarvestSlot.presentation(url: "https://example.com/", timesheet: signedOut) == .idle)
    }

    @Test func lastEntryPrefersLaterUpdatesThenLaterRows() {
        let entries = [entry(1, hours: 1, updatedAt: "b"), entry(2, hours: 1, updatedAt: "a"), entry(3, hours: 1, updatedAt: "b")]
        #expect(HarvestSlot.lastEntry(in: entries)?.id == 3)
        #expect(HarvestSlot.lastEntry(in: []) == nil)
    }

    @Test func formatsClockAndDuration() {
        #expect(HarvestSlot.clock(0) == "0:00:00")
        #expect(HarvestSlot.clock(783.9) == "0:13:03")
        #expect(HarvestSlot.clock(3 * 3600 + 5 * 60 + 9) == "3:05:09")
        #expect(HarvestSlot.duration(3.25 * 3600) == "3:15")
        #expect(HarvestSlot.duration(89) == "0:01")
        #expect(HarvestSlot.duration(-5) == "0:00")
    }

    @Test func entryTitleFallsBackToNotes() {
        #expect(entry(1, hours: 0, project: "", task: "", notes: "Planning").title == "Planning")
        #expect(entry(1, hours: 0, task: "", notes: "Planning").detail == "Planning")
        #expect(entry(1, hours: 0).title == "Website")
        #expect(entry(1, hours: 0).detail == "Design")
    }

    @Test func recognizesHarvestHosts() {
        #expect(HarvestSlot.isHarvest("https://harvestapp.com/time"))
        #expect(HarvestSlot.isHarvest("https://example.harvestapp.com/time"))
        #expect(!HarvestSlot.isHarvest("https://harvestapp.com.example.org/"))
        #expect(HarvestSlot.isSignIn("https://id.getharvest.com/"))
        #expect(!HarvestSlot.isSignIn("https://example.harvestapp.com/"))
    }
}
