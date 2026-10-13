import Foundation
import Testing
@testable import LittleLogCore

struct CareCelebrationTests {
    private let fixture = LogRulesTests()
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/New_York")!
        return result
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test(arguments: Array(0...35))
    func onlyFourWeeklyBirthdaysAreEligible(day: Int) {
        let child = ChildProfile(familyID: UUID(), name: "Robin",
                                 birthDate: date("2026-09-12T23:55:00-04:00"))
        let now = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: child.birthDate!))!
            .addingTimeInterval(12 * 3600)
        let celebration = AgeCelebration(child: child, at: now, calendar: calendar)
        #expect((celebration != nil) == [7, 14, 21, 28].contains(day))
        if let celebration { #expect(celebration.week == day / 7) }
    }

    @Test(arguments: [
        ("2026-03-07T23:55:00-05:00", "2026-03-14T00:01:00-04:00"),
        ("2026-10-31T23:55:00-04:00", "2026-11-07T00:01:00-05:00")
    ])
    func calendarBirthdaySurvivesDaylightSaving(birth: String, today: String) throws {
        let child = ChildProfile(familyID: UUID(), name: "Robin", birthDate: date(birth))
        #expect(try #require(AgeCelebration(child: child, at: date(today), calendar: calendar)).week == 1)
    }

    @Test func birthdayUsesActualAgeAndOffersAnUpcomingChapterWithoutAFalseDeadline() throws {
        let child = ChildProfile(familyID: UUID(), name: "Robin", birthDate: date("2026-09-12T00:00:00-04:00"),
                                 gestationalAgeAtBirthDays: 35 * 7 + 4)
        let weekOne = try #require(AgeCelebration(child: child, at: date("2026-09-19T12:00:00-04:00"), calendar: calendar))
        #expect(weekOne.nextCheckpoint == nil)
        let weekFour = try #require(AgeCelebration(child: child, at: date("2026-10-10T12:00:00-04:00"), calendar: calendar))
        #expect(weekFour.week == 4)
        #expect(weekFour.nextCheckpoint == 2)
        #expect(MilestoneAge(child: child, now: date("2026-10-10T12:00:00-04:00"), calendar: calendar)?.current == nil)
    }

    @Test func unknownFutureAndInvalidBirthDatesDoNotCelebrate() {
        for birth in [nil, date("2026-10-12T12:00:00-04:00"), Date(timeIntervalSince1970: .nan)] {
            let child = ChildProfile(familyID: UUID(), name: "Robin", birthDate: birth)
            #expect(AgeCelebration(child: child, at: date("2026-10-11T12:00:00-04:00"), calendar: calendar) == nil)
        }
    }

    @Test func receiptIsScopedToChildAndBirthdayNotNameOrAppearance() throws {
        var child = ChildProfile(familyID: UUID(), name: "Robin", birthDate: date("2026-09-12T00:00:00-04:00"))
        let now = date("2026-09-19T12:00:00-04:00")
        let original = try #require(AgeCelebration(child: child, at: now, calendar: calendar))
        child.name = "Robin Rose"; child.gender = .girl
        #expect(AgeCelebration(child: child, at: now, calendar: calendar)?.receiptKey == original.receiptKey)
        child.id = UUID()
        #expect(AgeCelebration(child: child, at: now, calendar: calendar)?.receiptKey != original.receiptKey)
    }

    private func pump(_ total: Decimal, pumperID: UUID? = nil) -> PumpSession {
        PumpSession(familyID: fixture.familyID, motherID: pumperID ?? fixture.personID,
                    occurredAt: fixture.now.addingTimeInterval(-60), authorID: fixture.personID,
                    totalML: total, unit: .ml)
    }
    private func put(_ value: RecordValue, in snapshot: inout FamilySnapshot, deleted: Bool = false) {
        let revision = RecordRevision(id: UUID(), recordID: value.id, parentIDs: [], value: value,
                                      date: fixture.now, editorID: fixture.personID, deleted: deleted)
        snapshot.records.removeAll { $0.id == value.id }
        snapshot.records.append(ProjectedRecord(revision: revision, heads: [revision]))
    }
    private func detect(_ pump: PumpSession, in snapshot: FamilySnapshot, actor: UUID? = nil) -> PumpingPersonalRecord? {
        PumpingPersonalRecord.detect(newSession: pump, in: snapshot, actorID: actor ?? fixture.personID, at: fixture.now)
    }

    @Test func firstSessionTiesAndSmallerSessionsAreQuiet() {
        var (snapshot, _) = fixture.fixture()
        #expect(detect(pump(200), in: snapshot) == nil)
        put(.pumping(pump(200)), in: &snapshot)
        #expect(detect(pump(200), in: snapshot) == nil)
        #expect(detect(pump(150), in: snapshot) == nil)
        #expect(detect(pump(Decimal(string: "200.01")!), in: snapshot)?.previousML == 200)
    }

    @Test func comparisonUsesCanonicalMillilitersAndSplitTotalsOnce() throws {
        var (snapshot, _) = fixture.fixture()
        var previous = pump(180); previous.unit = .oz
        put(.pumping(previous), in: &snapshot)
        var split = pump(210); split.leftML = 100; split.rightML = 110
        let event = try #require(detect(split, in: snapshot))
        #expect(event.totalML == 210)
        split.unit = .oz
        #expect(detect(split, in: snapshot) == event)
    }

    @Test func siriPumpingUsesTheSamePersonalHistory() {
        var (snapshot, _) = fixture.fixture()
        put(.pumping(pump(100)), in: &snapshot)
        var spoken = pump(150); spoken.source = "Siri / Shortcuts"
        #expect(detect(spoken, in: snapshot)?.previousML == 100)
        #expect(detect(spoken, in: snapshot, actor: UUID()) == nil)
    }

    @Test func otherPeopleOtherFamiliesDeletedAndFutureSessionsDoNotSetPersonalRecord() {
        var (snapshot, _) = fixture.fixture()
        put(.pumping(pump(100)), in: &snapshot)
        put(.pumping(pump(500, pumperID: UUID())), in: &snapshot)
        var foreign = pump(600); foreign.familyID = UUID()
        put(.pumping(foreign), in: &snapshot)
        put(.pumping(pump(700)), in: &snapshot, deleted: true)
        var future = pump(800); future.occurredAt = fixture.now.addingTimeInterval(3600)
        put(.pumping(future), in: &snapshot)
        #expect(detect(pump(150), in: snapshot)?.previousML == 100)
    }

    @Test func helpersImportsEditsAndInvalidSessionsDoNotCelebrate() {
        var (snapshot, _) = fixture.fixture()
        let previous = pump(100)
        put(.pumping(previous), in: &snapshot)
        var edited = previous; edited.totalML = 200
        #expect(detect(edited, in: snapshot) == nil)
        #expect(detect(pump(200), in: snapshot, actor: UUID()) == nil)
        var helper = pump(200); helper.authorID = UUID()
        #expect(detect(helper, in: snapshot) == nil)
        var imported = pump(200); imported.source = "JSONL"
        #expect(detect(imported, in: snapshot) == nil)
        #expect(detect(pump(0), in: snapshot) == nil)
        #expect(detect(pump(.nan), in: snapshot) == nil)
    }

    @Test func mergedPumpingHistoryStillSetsThePreviousRecord() {
        var (snapshot, _) = fixture.fixture()
        let alias = Caregiver(familyID: fixture.familyID, name: "Sam old", isMother: true,
                              mergedIntoID: fixture.personID)
        put(.caregiver(alias), in: &snapshot, deleted: true)
        put(.pumping(pump(300, pumperID: alias.id)), in: &snapshot)
        #expect(detect(pump(250), in: snapshot) == nil)
        #expect(detect(pump(350), in: snapshot)?.previousML == 300)
    }
}
