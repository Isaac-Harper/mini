import Foundation
import Testing
import MiniRules

struct EveningTintTests {
    let sunrise = Date(timeIntervalSinceReferenceDate: 7 * 3600)
    let sunset = Date(timeIntervalSinceReferenceDate: 18 * 3600)
    let nextSunrise = Date(timeIntervalSinceReferenceDate: 31 * 3600)

    func strength(minutesAfterSunset minutes: Double) -> Double {
        EveningTint.strength(at: sunset.addingTimeInterval(minutes * 60), sunrises: [sunrise, nextSunrise], sunsets: [sunset])
    }

    @Test func noWeatherDataMeansNoTint() {
        #expect(EveningTint.strength(at: sunset.addingTimeInterval(3600), sunrises: [], sunsets: []) == 0)
    }

    @Test func dataFromLongAgoMeansNoTint() {
        #expect(EveningTint.strength(at: nextSunrise.addingTimeInterval(2 * 86400), sunrises: [sunrise, nextSunrise], sunsets: [sunset]) == 0)
    }

    @Test func daytimeIsClearAndNightIsFull() {
        #expect(strength(minutesAfterSunset: -180) == 0)
        #expect(strength(minutesAfterSunset: 180) == 1)
        #expect(EveningTint.strength(at: sunrise.addingTimeInterval(-3600), sunrises: [sunrise, nextSunrise], sunsets: [sunset]) == 1)
    }

    @Test func easesInAroundSunset() {
        #expect(strength(minutesAfterSunset: -10) == 0)
        #expect(strength(minutesAfterSunset: 0) == 0.5)
        #expect(strength(minutesAfterSunset: 10) == 1)
        #expect(strength(minutesAfterSunset: -5) < strength(minutesAfterSunset: 5))
        #expect(strength(minutesAfterSunset: -5) > 0)
    }

    @Test func easesOutAroundSunrise() {
        func strength(minutesAfterSunrise minutes: Double) -> Double {
            EveningTint.strength(at: nextSunrise.addingTimeInterval(minutes * 60), sunrises: [sunrise, nextSunrise], sunsets: [sunset])
        }
        #expect(strength(minutesAfterSunrise: -10) == 1)
        #expect(strength(minutesAfterSunrise: 0) == 0.5)
        #expect(strength(minutesAfterSunrise: 10) == 0)
        #expect(strength(minutesAfterSunrise: 60) == 0)
    }
}
