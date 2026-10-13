import Foundation
import Testing
@testable import LittleLogCore

struct PumpingAnalyticsTests {
    let familyID = UUID()
    let motherID = UUID()
    let authorID = UUID()
    let zone = TimeZone(identifier: "America/New_York")!

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func pump(at text: String, totalML: Decimal = 105) -> PumpSession {
        PumpSession(familyID: familyID, motherID: motherID, occurredAt: date(text),
                    authorID: authorID, totalML: totalML, unit: .ml)
    }

    @Test func pumpingIsScopedToFamilyAndCaregiverAndCountsEachTotalOnce() {
        var split = pump(at: "2026-09-24T08:00:00-04:00")
        split.leftML = 60
        split.rightML = 45
        var anotherCaregiver = split
        anotherCaregiver.id = UUID()
        anotherCaregiver.motherID = UUID()
        var anotherFamily = split
        anotherFamily.id = UUID()
        anotherFamily.familyID = UUID()
        let totalOnly = pump(at: "2026-09-24T09:00:00-04:00", totalML: Decimal(string: "73.93")!)
        let days = LogAnalytics.pumpingDays(sessions: [split, anotherCaregiver, anotherFamily, totalOnly],
                                           familyID: familyID, motherID: motherID, count: 7,
                                           now: date("2026-09-24T12:00:00-04:00"), timeZone: zone)
        #expect(days.count == 7)
        #expect(days.last?.totalML == Decimal(string: "178.93"))
        #expect(days.last?.sessions == 2)
        #expect(days.dropLast().allSatisfy { $0.sessions == 0 && $0.totalML == 0 })
        // The person entering a session does not change which caregiver it belongs to.
        #expect(split.authorID != split.motherID)
        #expect(VolumeUnit.oz.quantity(days.last!.totalML) == "5.96 oz")
    }

    @Test func customRangeIncludesMidnightAndCutoffButExcludesOlderAndFutureSessions() {
        let times = ["2026-09-19T23:59:59-04:00", "2026-09-20T00:00:00-04:00",
                     "2026-09-20T23:59:59-04:00", "2026-09-21T00:00:00-04:00",
                     "2026-09-21T12:00:00-04:00", "2026-09-21T12:00:01-04:00",
                     "2026-09-22T00:00:00-04:00"]
        let days = LogAnalytics.pumpingDays(sessions: times.map { pump(at: $0) }, familyID: familyID,
                                           motherID: motherID, count: 2,
                                           now: date("2026-09-21T12:00:00-04:00"), timeZone: zone)
        #expect(days.map(\.date) == [date("2026-09-20T00:00:00-04:00"), date("2026-09-21T00:00:00-04:00")])
        #expect(days.map(\.sessions) == [2, 2])
        #expect(days.map(\.totalML) == [210, 210])
    }

    @Test(arguments: [
        ("2026-03-08T01:30:00-05:00", "2026-03-08T03:30:00-04:00", "2026-03-09T12:00:00-04:00", 23),
        ("2026-11-01T01:30:00-04:00", "2026-11-01T01:30:00-05:00", "2026-11-02T12:00:00-05:00", 25)
    ])
    func calendarBucketsRespectDaylightSavingTransitions(first: String, second: String, end: String, hours: Int) {
        let days = LogAnalytics.pumpingDays(sessions: [pump(at: first), pump(at: second)], familyID: familyID,
                                           motherID: motherID, count: 2, now: date(end), timeZone: zone)
        #expect(days.map(\.sessions) == [2, 0])
        #expect(days[1].date.timeIntervalSince(days[0].date) == Double(hours * 3600))
    }

    @Test(arguments: [0, 1, 7, 30, 366])
    func emptyRangesPreserveCalendarDays(count: Int) {
        let days = LogAnalytics.pumpingDays(sessions: [], familyID: familyID, motherID: motherID,
                                           count: count, now: date("2026-09-24T12:00:00-04:00"), timeZone: zone)
        #expect(days.count == count)
        #expect(days.allSatisfy { $0.sessions == 0 && $0.totalML == 0 })
        #expect(Set(days.map(\.id)).count == count)
    }
}
