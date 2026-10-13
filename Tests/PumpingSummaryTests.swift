import Foundation
import Testing
@testable import LittleLogCore

struct PumpingSummaryTests {
    private let fixture = LogRulesTests()
    private var now: Date { date("2026-10-04T10:00:00-04:00") }
    private var start: Date { now.addingTimeInterval(-86400) }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func put(_ value: RecordValue, in snapshot: inout FamilySnapshot, deleted: Bool = false) {
        let revision = RecordRevision(
            id: UUID(), recordID: value.id, parentIDs: [], value: value,
            date: now, editorID: fixture.personID, deleted: deleted)
        snapshot.records.removeAll { $0.id == value.id }
        snapshot.records.append(ProjectedRecord(revision: revision, heads: [revision]))
    }

    private func pump(at time: Date? = nil, totalML: Decimal = 105) -> PumpSession {
        PumpSession(
            familyID: fixture.familyID, motherID: fixture.personID,
            occurredAt: time ?? now, authorID: UUID(), totalML: totalML, unit: .ml)
    }

    private func summary(_ snapshot: FamilySnapshot, start: Date? = nil, end: Date? = nil) -> PumpingSummary? {
        PumpingSummary(snapshot: snapshot, caregiverID: fixture.personID,
                       start: start ?? self.start, end: end ?? now)
    }

    @Test func totalsFollowPumperNotAuthorAndStaySeparateFromChildrenAndOtherPumpers() throws {
        var (snapshot, child) = fixture.fixture()
        var split = pump()
        split.leftML = 60
        split.rightML = 45
        put(.pumping(split), in: &snapshot)
        put(.pumping(pump(totalML: Decimal(string: "73.93")!)), in: &snapshot)
        var otherPumper = pump(totalML: 900)
        otherPumper.motherID = UUID()
        otherPumper.authorID = fixture.personID
        put(.pumping(otherPumper), in: &snapshot)
        var otherFamily = pump(totalML: 1000)
        otherFamily.familyID = UUID()
        put(.pumping(otherFamily), in: &snapshot)
        put(.activity(fixture.activity(child, payload: .bottle(Bottle(milkML: 90, formulaML: 30, unit: .ml)), date: now)), in: &snapshot)
        let before = try #require(summary(snapshot))
        #expect(before.totalML == Decimal(string: "178.93"))
        #expect(before.sessions == 2)
        #expect(VolumeUnit.oz.quantity(before.totalML) == "5.96 oz")
        let intake = ActivitySummary(activities: snapshot.activities, childID: child.id, start: start, end: now)
        #expect(intake.totalML == 120 && intake.bottles == 1)
        let sibling = ChildProfile(familyID: fixture.familyID, name: "Jamie")
        put(.child(sibling), in: &snapshot)
        put(.activity(fixture.activity(sibling, payload: .bottle(Bottle(milkML: 120, formulaML: 0, unit: .ml)), date: now)), in: &snapshot)
        #expect(summary(snapshot) == before)
    }

    @Test func rollingAndTodayUseTheDashboardWindowAndExcludeFutureRecords() throws {
        var (snapshot, _) = fixture.fixture()
        for time in [start, start.addingTimeInterval(1), date("2026-10-03T23:59:59-04:00"),
                     date("2026-10-04T00:00:00-04:00"), now, now.addingTimeInterval(1)] {
            put(.pumping(pump(at: time, totalML: 30)), in: &snapshot)
        }
        let rolling = try #require(summary(snapshot))
        #expect(rolling.sessions == 4 && rolling.totalML == 120)
        let midnight = date("2026-10-04T00:00:00-04:00")
        let today = try #require(summary(snapshot, start: midnight.addingTimeInterval(-0.001)))
        #expect(today.sessions == 2 && today.totalML == 60)
        #expect(try #require(summary(snapshot, start: now)).sessions == 0)
    }

    @Test func onlyActivePumpingCaregiversHaveASummaryEvenWithNoRecordedSessions() throws {
        var (snapshot, _) = fixture.fixture()
        let empty = try #require(summary(snapshot))
        #expect(empty.sessions == 0 && empty.totalML == 0)
        #expect(PumpingSummary(snapshot: snapshot, caregiverID: UUID(), start: start, end: now) == nil)
        var person = empty.caregiver
        person.isMother = false
        put(.caregiver(person), in: &snapshot)
        put(.pumping(pump()), in: &snapshot)
        #expect(summary(snapshot) == nil)
        person.isMother = true
        put(.caregiver(person), in: &snapshot, deleted: true)
        #expect(summary(snapshot) == nil)
        person.familyID = UUID()
        put(.caregiver(person), in: &snapshot)
        #expect(summary(snapshot) == nil)
        snapshot.family = nil
        #expect(summary(snapshot) == nil)
    }

    @Test func mergedHistoryEditsAndDeletionsMatchTheCurrentProjection() throws {
        var (snapshot, _) = fixture.fixture()
        let duplicate = Caregiver(familyID: fixture.familyID, name: "Sam old", isMother: true,
                                  mergedIntoID: fixture.personID)
        put(.caregiver(duplicate), in: &snapshot, deleted: true)
        var session = pump(totalML: 90)
        session.motherID = duplicate.id
        put(.pumping(session), in: &snapshot)
        put(.pumping(pump(totalML: 60)), in: &snapshot)
        #expect(try #require(summary(snapshot)).totalML == 150)
        #expect(PumpingSummary(snapshot: snapshot, caregiverID: duplicate.id, start: start, end: now) == summary(snapshot))
        session.totalML = 120
        put(.pumping(session), in: &snapshot)
        #expect(try #require(summary(snapshot)).totalML == 180)
        put(.pumping(session), in: &snapshot, deleted: true)
        let afterDeletion = try #require(summary(snapshot))
        #expect(afterDeletion.totalML == 60 && afterDeletion.sessions == 1)
    }

    @Test(arguments: ["2026-03-08T23:30:00-04:00", "2026-11-01T23:30:00-05:00"])
    func todayUsesFamilyMidnightAcrossDaylightSavingChanges(endText: String) throws {
        var (snapshot, _) = fixture.fixture()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let end = date(endText)
        let midnight = calendar.startOfDay(for: end)
        for time in [midnight.addingTimeInterval(-1), midnight, end, end.addingTimeInterval(1)] {
            put(.pumping(pump(at: time, totalML: 30)), in: &snapshot)
        }
        let today = try #require(summary(snapshot, start: midnight.addingTimeInterval(-0.001), end: end))
        #expect(today.sessions == 2 && today.totalML == 60)
    }
}
