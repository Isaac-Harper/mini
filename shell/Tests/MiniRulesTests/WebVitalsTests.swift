import Testing
import MiniRules

struct WebVitalsTests {
    @Test func ratingsFollowGooglesThresholdsInclusiveOfTheGoodLimit() {
        #expect(WebVitals.rating(of: .largestContentfulPaint, value: 2500) == .good)
        #expect(WebVitals.rating(of: .largestContentfulPaint, value: 2501) == .needsImprovement)
        #expect(WebVitals.rating(of: .largestContentfulPaint, value: 4000) == .needsImprovement)
        #expect(WebVitals.rating(of: .largestContentfulPaint, value: 4001) == .poor)
        #expect(WebVitals.rating(of: .interactionToNextPaint, value: 200) == .good)
        #expect(WebVitals.rating(of: .interactionToNextPaint, value: 350) == .needsImprovement)
        #expect(WebVitals.rating(of: .interactionToNextPaint, value: 501) == .poor)
        #expect(WebVitals.rating(of: .cumulativeLayoutShift, value: 0.1) == .good)
        #expect(WebVitals.rating(of: .cumulativeLayoutShift, value: 0.2) == .needsImprovement)
        #expect(WebVitals.rating(of: .cumulativeLayoutShift, value: 0.26) == .poor)
        #expect(WebVitals.rating(of: .timeToFirstByte, value: 800) == .good)
        #expect(WebVitals.rating(of: .timeToFirstByte, value: 1800) == .needsImprovement)
        #expect(WebVitals.rating(of: .timeToFirstByte, value: 1801) == .poor)
    }

    @Test func negativeReportsMeanNotMeasured() {
        let vitals = WebVitals(reportedLCP: -1, inp: -1, cls: 0, ttfb: 120)
        #expect(vitals.largestContentfulPaint == nil)
        #expect(vitals.interactionToNextPaint == nil)
        #expect(vitals.cumulativeLayoutShift == 0)
        #expect(vitals.timeToFirstByte == 120)
    }

    @Test func onlyPoorLayoutShiftOrPaintWarns() {
        #expect(!WebVitals(reportedLCP: 1200, inp: 900, cls: 0.02, ttfb: 3000).needsWarning)
        #expect(WebVitals(reportedLCP: 4500, inp: -1, cls: 0, ttfb: 100).needsWarning)
        #expect(WebVitals(reportedLCP: 900, inp: -1, cls: 0.3, ttfb: 100).needsWarning)
        #expect(!WebVitals(reportedLCP: 3000, inp: -1, cls: 0.2, ttfb: 100).needsWarning)
        #expect(!WebVitals().needsWarning)
    }

    @Test func valuesFormatCompactly() {
        #expect(WebVitals.formatted(.largestContentfulPaint, value: 142.4) == "142ms")
        #expect(WebVitals.formatted(.largestContentfulPaint, value: 1430) == "1.4s")
        #expect(WebVitals.formatted(.timeToFirstByte, value: 12_400) == "12s")
        #expect(WebVitals.formatted(.cumulativeLayoutShift, value: 0.034) == "0.03")
        #expect(WebVitals.formatted(.interactionToNextPaint, value: nil) == "\u{2026}")
        #expect(DurationText.milliseconds(999.6) == "1000ms")
    }
}
