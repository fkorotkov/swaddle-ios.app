import Foundation
import Testing
@testable import LittleLogCore

struct MilestoneTests {
    let familyID = UUID()
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func catalogContainsEveryReviewedSkillAndDistinctSourceIdentities() {
        #expect(MilestoneCatalog.checkpoints.map { MilestoneCatalog.skills(at: $0).count } == [11, 13, 12, 13, 10, 13, 15, 13])
        #expect(Set(MilestoneCatalog.all.map(\.id)).count == 106)
        #expect(MilestoneCatalog.cdcSkills.allSatisfy { $0.sourceVersion == "cdc-2026-10-10" && $0.sourceURL.hasPrefix("https://www.cdc.gov/act-early/milestones/") })
        #expect(MilestoneCatalog.skills(at: 9).first { $0.id == "cdc-9-sits_without" }?.motorWindow == nil)
        #expect(MilestoneCatalog.skill("who-sitting")?.motorWindow == 3.8...9.2)
        #expect(MilestoneCatalog.skill("who-walking-assisted")?.motorWindow == 6.0...13.7)
    }

    @Test func newbornLooksAheadWithoutInventingACurrentChecklist() throws {
        let child = ChildProfile(familyID: familyID, name: "Robin", birthDate: date("2026-09-01T00:00:00-04:00"))
        let age = try #require(MilestoneAge(child: child, now: date("2026-10-10T12:00:00-04:00"), calendar: calendar))
        #expect(age.current == nil)
        #expect(age.upcoming == 2)
        #expect(age.suggested == 2)
        #expect(!age.isCorrected)
        #expect(MilestoneAge(child: ChildProfile(familyID: familyID, name: "Unknown"), now: .now, calendar: calendar) == nil)
    }

    @Test func checklistAgeUsesCalendarMonthsAndYoungerCheckpoint() throws {
        let child = ChildProfile(familyID: familyID, name: "Robin", birthDate: date("2026-01-10T00:00:00-05:00"))
        let before = try #require(MilestoneAge(child: child, now: date("2026-03-09T23:59:00-04:00"), calendar: calendar))
        let birthday = try #require(MilestoneAge(child: child, now: date("2026-03-10T00:00:00-04:00"), calendar: calendar))
        let between = try #require(MilestoneAge(child: child, now: date("2026-04-20T12:00:00-04:00"), calendar: calendar))
        #expect(before.current == nil)
        #expect(birthday.current == 2)
        #expect(between.current == 2 && between.upcoming == 4)
    }

    @Test func prematurityUsesDueDateThroughSecondBirthday() throws {
        let child = ChildProfile(familyID: familyID, name: "Robin", birthDate: date("2024-09-01T00:00:00-04:00"), gestationalAgeAtBirthDays: 32 * 7)
        let early = try #require(MilestoneAge(child: child, now: date("2024-10-01T00:00:00-04:00"), calendar: calendar))
        #expect(early.isCorrected && early.beforeDueDate && early.current == nil)
        let corrected = try #require(MilestoneAge(child: child, now: date("2024-12-27T00:00:00-05:00"), calendar: calendar))
        #expect(corrected.isCorrected && corrected.current == 2 && corrected.upcoming == 4)
        let beforeTwo = try #require(MilestoneAge(child: child, now: date("2026-08-31T00:00:00-04:00"), calendar: calendar))
        #expect(beforeTwo.isCorrected && beforeTwo.current == 18)
        let two = try #require(MilestoneAge(child: child, now: date("2026-09-01T00:00:00-04:00"), calendar: calendar))
        #expect(!two.isCorrected && two.current == 24 && two.upcoming == nil)
        let older = try #require(MilestoneAge(child: child, now: date("2026-12-01T00:00:00-05:00"), calendar: calendar))
        #expect(older.current == nil && older.upcoming == nil)
    }

    func fixture() -> (FamilySnapshot, ChildProfile, Caregiver) {
        let caregiver = Caregiver(familyID: familyID, name: "Sam")
        let child = ChildProfile(familyID: familyID, name: "Robin", birthDate: date("2026-09-01T00:00:00-04:00"))
        return (FamilySnapshot(family: Family(id: familyID, name: "Family", timeZoneIdentifier: "America/New_York", ownerID: caregiver.id), records: RevisionProjection.project([
            revision(.child(child)), revision(.caregiver(caregiver))
        ])), child, caregiver)
    }
    func observation(_ child: ChildProfile, _ author: UUID) -> MilestoneObservation {
        .init(familyID: familyID, childID: child.id, skillID: "cdc-2-smilestalk2", sourceVersion: "cdc-2026-10-10", skillTitle: "Smiles when you talk to or smile at her", status: .seen, firstNoticedAt: date("2026-10-07T12:00:00-04:00"), authorID: author, recordedAt: date("2026-10-09T12:00:00-04:00"))
    }
    func revision(_ value: RecordValue, parents: Set<UUID> = [], deleted: Bool = false) -> RecordRevision {
        .init(id: UUID(), recordID: value.id, parentIDs: parents, value: value, date: date("2026-10-10T12:00:00-04:00"), editorID: UUID(), deleted: deleted)
    }

    @Test func observationsRoundTripWithoutChangingCareTotalsOrSearch() throws {
        var (snapshot, child, author) = fixture()
        let record = observation(child, author.id)
        let envelope = RecordEnvelope(value: .milestone(record))
        #expect(envelope.version == 4)
        #expect(try JSONDecoder().decode(RecordEnvelope.self, from: JSONEncoder().encode(envelope)) == envelope)
        snapshot.records.append(contentsOf: RevisionProjection.project([revision(.milestone(record))]))
        #expect(snapshot.milestoneObservations == [record])
        #expect(snapshot.activities.isEmpty && snapshot.pumps.isEmpty && snapshot.recentCare(for: child.id).isEmpty)
        #expect(CareSearchCatalog.documents(in: snapshot).isEmpty)
    }

    @Test func independentCaregiversAndConcurrentCorrectionsRetainHistory() {
        var (snapshot, child, author) = fixture()
        let original = observation(child, author.id)
        var other = original; other.id = UUID(); other.authorID = UUID(); other.status = .unsure; other.firstNoticedAt = nil
        let base = revision(.milestone(original))
        var editA = original; editA.note = "Morning"
        var editB = original; editB.note = "Evening"
        let a = revision(.milestone(editA), parents: [base.id])
        let b = revision(.milestone(editB), parents: [base.id])
        snapshot.records += RevisionProjection.project([base, a, b, revision(.milestone(other))])
        #expect(snapshot.milestoneObservations.count == 2)
        #expect(snapshot.record(original.id)?.hasConflict == true)
        #expect(snapshot.record(original.id)?.heads.map(\.value).contains(.milestone(editA)) == true)
        #expect(snapshot.record(original.id)?.heads.map(\.value).contains(.milestone(editB)) == true)
        #expect(snapshot.milestoneObservations.contains(other))
    }

    @Test func deletionAndForeignChildDoNotLeakIntoJourney() {
        var (snapshot, child, author) = fixture()
        let first = revision(.milestone(observation(child, author.id)))
        var foreign = observation(child, author.id); foreign.id = UUID(); foreign.familyID = UUID()
        var sibling = observation(child, author.id); sibling.id = UUID(); sibling.childID = UUID()
        snapshot.records += RevisionProjection.project([first, revision(first.value, parents: [first.id], deleted: true), revision(.milestone(foreign)), revision(.milestone(sibling))])
        #expect(snapshot.milestoneObservations.isEmpty)
    }

    @Test func validationRejectsFutureDatesWrongChildAndInvalidFirstNoticedDate() throws {
        let (snapshot, child, author) = fixture()
        let now = date("2026-10-10T12:00:00-04:00")
        let original = observation(child, author.id)
        try LogRules.validate(.milestone(original), in: snapshot, now: now)
        var changed = original; changed.firstNoticedAt = date("2026-08-01T12:00:00-04:00")
        #expect(throws: LogError.self) { try LogRules.validate(.milestone(changed), in: snapshot, now: now) }
        changed = original; changed.firstNoticedAt = now
        #expect(throws: LogError.self) { try LogRules.validate(.milestone(changed), in: snapshot, now: now) }
        changed = original; changed.status = .notYet
        #expect(throws: LogError.self) { try LogRules.validate(.milestone(changed), in: snapshot, now: now) }
        changed = original; changed.childID = UUID()
        #expect(throws: LogError.self) { try LogRules.validate(.milestone(changed), in: snapshot, now: now) }
        changed = original; changed.familyID = UUID()
        #expect(throws: LogError.self) { try LogRules.validate(.milestone(changed), in: snapshot, now: now) }
        changed = original; changed.recordedAt = now.addingTimeInterval(1)
        #expect(throws: LogError.self) { try LogRules.validate(.milestone(changed), in: snapshot, now: now) }
    }
}
