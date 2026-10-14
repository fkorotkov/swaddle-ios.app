import Foundation
import Testing
@testable import LittleLogCore

struct DemoFamilyTests {
    @Test(arguments: ["2026-10-14T00:01:00Z", "2026-03-08T08:00:00Z", "2026-11-01T07:00:00Z", "2028-02-29T22:00:00Z"])
    func validExamplesAcrossMidnightDSTAndLeapYear(_ timestamp: String) throws {
        let now = try #require(ISO8601DateFormatter().date(from: timestamp))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let example = try DemoFamily.make(now: now, calendar: calendar)
        let snapshot = example.snapshot
        #expect(snapshot.children.count == 1)
        #expect(snapshot.caregivers.count == 2)
        #expect(snapshot.caregivers.filter(\.isMother).count == 1)
        #expect(Set(example.records.map(\.id)).count == example.records.count)
        for record in example.records { try LogRules.validate(record, in: snapshot, now: now) }
        #expect(snapshot.activities.allSatisfy { $0.occurredAt >= example.child.birthDate! && $0.occurredAt <= now })
        #expect(snapshot.pumps.allSatisfy { $0.occurredAt <= now && $0.leftML! + $0.rightML! == $0.totalML })
        #expect(snapshot.pumps.count == 124)
        let recent = ActivitySummary(activities: snapshot.activities, childID: example.child.id, start: now.addingTimeInterval(-86_400), end: now)
        #expect(recent.totalML > 700 && recent.totalML < 1_000)
        #expect(recent.wet == 6)
        #expect(Set(snapshot.activities.map(\.payload.kind)) == Set(ActivityKind.allCases))
    }

    @Test func fullTermBirthIsSixDaysBeforeDueDateWithoutAdjustedPercentiles() throws {
        let now = try #require(ISO8601DateFormatter().date(from: "2026-10-14T18:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let example = try DemoFamily.make(now: now, calendar: calendar)
        let age = try #require(ChildAge(child: example.child, at: now, calendar: calendar))
        #expect(age.correctedDays == nil)
        #expect(example.child.gestationalAgeAtBirthDays == 274)
        #expect(calendar.dateComponents([.day], from: example.child.birthDate!, to: age.estimatedDueDate!).day == 6)
        for activity in example.snapshot.activities {
            switch activity.payload {
            case .weight(let grams, _):
                let reading = try WHOWeightForAge.evaluate(grams: grams.double, child: example.child, at: activity.occurredAt, calendar: calendar, now: now)
                #expect((45...55).contains(reading.percentile))
                #expect(!reading.age.isCorrected)
            case .length(let cm, _, let position):
                let reading = try MeasurementForAge.evaluate(centimeters: cm.double, metric: .length, position: position, child: example.child, at: activity.occurredAt, calendar: calendar, now: now)
                #expect((50...60).contains(reading.percentile))
            case .headCircumference(let cm, _):
                let reading = try MeasurementForAge.evaluate(centimeters: cm.double, metric: .headCircumference, child: example.child, at: activity.occurredAt, calendar: calendar, now: now)
                #expect((40...50).contains(reading.percentile))
            default: break
            }
        }
    }

    @Test func separateSessionsCannotAddressEachOthersRecords() throws {
        let first = try DemoFamily.make(), second = try DemoFamily.make()
        #expect(first.family.id != second.family.id)
        #expect(Set(first.records.map(\.id)).isDisjoint(with: second.records.map(\.id)))
    }
}
