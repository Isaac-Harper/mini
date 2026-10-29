import Foundation
import Testing
import MiniRules

struct DayClosingTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
    let locale = Locale(identifier: "en_US_POSIX")

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func midnight(_ day: Int, month: Int = 10) -> Date { date(day, 0, month: month) }

    func candidate(_ identifier: Int, _ lastSelectedAt: Date, kept: Bool = false, children: [DayClosing.Candidate<Int>] = []) -> DayClosing.Candidate<Int> {
        DayClosing.Candidate(identifier: identifier, lastSelectedAt: lastSelectedAt, isKept: kept, children: children)
    }

    @Test func dayTurnsOverAtFourInTheMorning() {
        #expect(DayClosing.day(containing: date(28, 23), calendar: calendar) == midnight(28))
        #expect(DayClosing.day(containing: date(29, 3, 59), calendar: calendar) == midnight(28))
        #expect(DayClosing.day(containing: date(29, 4), calendar: calendar) == midnight(29))
        #expect(DayClosing.start(ofDay: midnight(29), calendar: calendar) == date(29, 4))
    }

    @Test func dayBoundaryAcrossDaylightSavingEnd() {
        #expect(DayClosing.day(containing: date(1, 3, 30, month: 11), calendar: calendar) == midnight(31))
        #expect(DayClosing.day(containing: date(1, 4, 30, month: 11), calendar: calendar) == midnight(1, month: 11))
    }

    @Test func newDayOnlyOncePerDay() {
        #expect(DayClosing.isNewDay(at: date(29, 9), lastClosedDay: nil, calendar: calendar))
        #expect(DayClosing.isNewDay(at: date(29, 9), lastClosedDay: midnight(28), calendar: calendar))
        #expect(!DayClosing.isNewDay(at: date(29, 9), lastClosedDay: midnight(29), calendar: calendar))
        #expect(!DayClosing.isNewDay(at: date(30, 2), lastClosedDay: midnight(29), calendar: calendar))
        #expect(DayClosing.isNewDay(at: date(30, 4), lastClosedDay: midnight(29), calendar: calendar))
    }

    @Test func previousActiveDaySkipsIdleDays() {
        let selections = [date(23, 10), date(24, 18), date(27, 9)]
        #expect(DayClosing.previousActiveDay(before: date(27, 9, 30), selections: selections, calendar: calendar) == midnight(24))
        #expect(DayClosing.previousActiveDay(before: date(29, 9), selections: selections, calendar: calendar) == midnight(27))
        #expect(DayClosing.previousActiveDay(before: date(27, 10), selections: [date(27, 9)], calendar: calendar) == nil)
        #expect(DayClosing.previousActiveDay(before: date(28, 10), selections: [date(28, 2)], calendar: calendar) == midnight(27))
    }

    @Test func foldsRootsNotSelectedDuringTheClosingDay() {
        let roots = [
            candidate(1, date(27, 15)),
            candidate(2, date(28, 3)),
            candidate(3, date(28, 4, 1)),
            candidate(4, date(26, 9), kept: true),
        ]
        #expect(DayClosing.rootsToFold(roots, selectedBefore: DayClosing.start(ofDay: midnight(28), calendar: calendar)) == [1, 2])
    }

    @Test func aRootFoldsOnlyWithItsWholeSubtree() {
        let roots = [
            candidate(1, date(20, 9), children: [candidate(2, date(20, 9)), candidate(3, date(28, 12))]),
            candidate(4, date(20, 9), children: [candidate(5, date(20, 9), kept: true)]),
            candidate(6, date(20, 9), children: [candidate(7, date(21, 9), children: [candidate(8, date(22, 9))])]),
        ]
        #expect(DayClosing.rootsToFold(roots, selectedBefore: DayClosing.start(ofDay: midnight(28), calendar: calendar)) == [6])
    }

    @Test func labelsUseTheWeekdayWithinAWeekThenTheDate() {
        #expect(DayClosing.label(forDay: midnight(27), now: date(28, 9), calendar: calendar, locale: locale) == "Tuesday")
        #expect(DayClosing.label(forDay: midnight(22), now: date(29, 2), calendar: calendar, locale: locale) == "Thursday")
        #expect(DayClosing.label(forDay: midnight(22), now: date(29, 9), calendar: calendar, locale: locale) == "Oct 22")
        #expect(DayClosing.label(forDay: midnight(28), now: date(29, 9), calendar: calendar, locale: locale) == "Wednesday")
    }

    @Test func titlesAndMessages() {
        #expect(DayClosing.groupTitle(label: "Tuesday", tabCount: 6) == "Tuesday \u{00B7} 6 tabs")
        #expect(DayClosing.groupTitle(label: "Tuesday", tabCount: 1) == "Tuesday \u{00B7} 1 tab")
        #expect(DayClosing.foldMessage(label: "Tuesday", tabCount: 6) == "Folded 6 tabs from Tuesday")
    }

    @Test func groupsExpireAfterTheArchiveWindow() {
        #expect(!DayClosing.isExpired(foldedAt: date(29, 9), now: date(29, 20, 59), window: 12 * 3600))
        #expect(DayClosing.isExpired(foldedAt: date(29, 9), now: date(29, 21), window: 12 * 3600))
    }
}
