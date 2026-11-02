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
        guard case .running(let timer, _) = HarvestSlot.presentation(url: "https://example.harvestapp.com/time", timesheet: timesheet) else {
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
            == .stopped(last: timesheet.entries[0], lastSeconds: 2 * 3600, todaySeconds: 3.25 * 3600))
        let empty = HarvestTimesheet(fetchedAt: 0, signedIn: true, entries: [])
        #expect(HarvestSlot.presentation(url: "https://example.harvestapp.com/time", timesheet: empty) == .stopped(last: nil, lastSeconds: 0, todaySeconds: 0))
    }

    @Test func stoppingKeepsTheClockWhereItWasAndResumingNeverStepsBack() throws {
        let start = "2026-01-05T09:00:00Z"
        let running = HarvestTimesheet(fetchedAt: fetchedAt.timeIntervalSince1970 * 1000, signedIn: true, entries: [
            entry(5, hours: 1.5, startedAt: start, updatedAt: start),
        ])
        let stoppedAt = fetchedAt.addingTimeInterval(427)
        let shownAtStop = HarvestSlot.seconds(of: running.entries[0], in: running, shownSeconds: [:], at: stoppedAt)
        #expect(shownAtStop == 5400 + 427)

        let stopped = HarvestTimesheet(fetchedAt: stoppedAt.timeIntervalSince1970 * 1000, signedIn: true, entries: [
            entry(5, hours: 1.62, updatedAt: "2026-01-05T10:37:07Z"),
        ])
        let carriedAtStop = HarvestSlot.carriedSeconds(from: running, shownSeconds: [:], into: stopped)
        #expect(HarvestSlot.presentation(url: "https://example.harvestapp.com/time", timesheet: stopped, shownSeconds: carriedAtStop)
            == .stopped(last: stopped.entries[0], lastSeconds: shownAtStop, todaySeconds: 1.62 * 3600))

        let resumedAt = stoppedAt.addingTimeInterval(60)
        let resumedStart = resumedAt.ISO8601Format()
        let resumed = HarvestTimesheet(fetchedAt: resumedAt.timeIntervalSince1970 * 1000, signedIn: true, entries: [
            entry(5, hours: 1.62, startedAt: resumedStart, updatedAt: resumedStart),
        ])
        let carriedAtResume = HarvestSlot.carriedSeconds(from: stopped, shownSeconds: carriedAtStop, into: resumed)
        guard case .running(let timer, _) = HarvestSlot.presentation(url: "https://example.harvestapp.com/time", timesheet: resumed, shownSeconds: carriedAtResume) else {
            Issue.record("expected a running timer")
            return
        }
        #expect(timer.elapsedSeconds(at: resumedAt) == shownAtStop)
        #expect(HarvestSlot.carriedSeconds(from: resumed, shownSeconds: carriedAtResume, into: HarvestTimesheet(fetchedAt: 0, signedIn: true, entries: [])).isEmpty)
    }

    @Test func editsInHarvestBeyondItsRoundingWin() {
        #expect(HarvestSlot.reconciled(reported: 5832, shown: 5827) == 5827)
        #expect(HarvestSlot.reconciled(reported: 5800, shown: 5827) == 5827)
        #expect(HarvestSlot.reconciled(reported: 7200, shown: 5827) == 7200)
        #expect(HarvestSlot.reconciled(reported: 5832, shown: nil) == 5832)
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
