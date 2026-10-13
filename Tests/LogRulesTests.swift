import Foundation
import Testing
@testable import LittleLogCore

struct LogRulesTests {
    let familyID = UUID()
    let personID = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    func fixture() -> (FamilySnapshot, ChildProfile) {
        let child = ChildProfile(familyID: familyID, name: "Robin")
        let mother = Caregiver(id: personID, familyID: familyID, name: "Sam", isMother: true)
        let values: [RecordValue] = [.child(child), .caregiver(mother)]
        return (FamilySnapshot(family: Family(id: familyID, name: "Family", timeZoneIdentifier: "America/New_York", ownerID: personID), records: RevisionProjection.project(values.map { .init(id: UUID(), recordID: $0.id, parentIDs: [], value: $0, date: now, editorID: personID, deleted: false) })), child)
    }
    func activity(_ child: ChildProfile, payload: ActivityPayload, date: Date? = nil) -> Activity {
        Activity(familyID: familyID, childID: child.id, occurredAt: date ?? now, authorID: personID, payload: payload)
    }
    @Test func singleChildNeedsNoParameterAndExplicitInvalidDoesNotFallback() throws {
        let (snapshot, child) = fixture()
        #expect(try LogRules.child(nil, in: snapshot).id == child.id)
        #expect(throws: LogError.self) { try LogRules.child(UUID(), in: snapshot) }
        #expect(throws: LogError.self) { try LogRules.child(nil, in: snapshot, ready: false) }
    }
    @Test func addingSecondChildRequiresDisambiguation() throws {
        var (snapshot, child) = fixture()
        let other = ChildProfile(familyID: familyID, name: "Jamie")
        let revision = RecordRevision(id: UUID(), recordID: other.id, parentIDs: [], value: .child(other), date: now, editorID: personID, deleted: false)
        snapshot.records.append(ProjectedRecord(revision: revision, heads: [revision]))
        #expect(throws: LogError.needsChild) { try LogRules.child(nil, in: snapshot) }
        #expect(try LogRules.child(child.id, in: snapshot).id == child.id)
        #expect(try LogRules.mother(nil, in: snapshot).id == personID)
    }
    @Test func widgetLinksRequireTheExactFamilyAndChild() throws {
        let (snapshot, child) = fixture()
        let valid = try #require(URL(string: "littlelog://today?family=\(familyID)&child=\(child.id)"))
        #expect(try LogDestination.resolve(valid, in: snapshot, ready: true) == .today(childID: child.id))
        for target in ["family=\(UUID())&child=\(child.id)", "family=\(familyID)&child=\(UUID())", "child=\(child.id)"] {
            let url = try #require(URL(string: "littlelog://today?\(target)"))
            #expect(throws: LogError.self) { try LogDestination.resolve(url, in: snapshot, ready: true) }
        }
        #expect(throws: LogError.self) { try LogDestination.resolve(valid, in: snapshot, ready: false) }
    }
    @Test func diaperUnionAndChildIsolation() {
        let (_, child) = fixture()
        var records: [Activity] = []
        for _ in 0..<4 { records.append(activity(child, payload: .diaper(.init(pee: true, poo: false)))) }
        records.append(activity(child, payload: .diaper(.init(pee: false, poo: true))))
        for _ in 0..<3 { records.append(activity(child, payload: .diaper(.init(pee: true, poo: true)))) }
        records.append(activity(ChildProfile(familyID: familyID, name: "Sibling"), payload: .diaper(.init(pee: true, poo: true))))
        let summary = ActivitySummary(activities: records, childID: child.id, end: now)
        #expect(summary.changes == 8 && summary.wet == 7 && summary.soiled == 4)
    }
    @Test func rollingWindowExcludesLowerBoundaryAndFuture() {
        let (_, child) = fixture()
        let payload = ActivityPayload.bottle(.init(milkML: 90, formulaML: 30, unit: .ml))
        let dates = [now.addingTimeInterval(-86400), now.addingTimeInterval(-86399), now, now.addingTimeInterval(1)]
        let summary = ActivitySummary(activities: dates.map { activity(child, payload: payload, date: $0) }, childID: child.id, start: now.addingTimeInterval(-86400), end: now)
        #expect(summary.bottles == 2 && summary.milkML == 180 && summary.formulaML == 60)
    }
    @Test func ouncesStayExactAndMixedBottleValidates() throws {
        #expect(VolumeUnit.oz.toML(3) == 90)
        #expect(VolumeUnit.oz.fromML(VolumeUnit.oz.toML(3)) == 3)
        let (snapshot, child) = fixture()
        try LogRules.validate(.activity(activity(child, payload: .bottle(.init(milkML: 60, formulaML: 30, unit: .oz)))), in: snapshot, now: now)
        #expect(throws: LogError.self) { try LogRules.validate(.activity(activity(child, payload: .bottle(.init(milkML: -1, formulaML: 90, unit: .ml)))), in: snapshot, now: now) }
        #expect(throws: LogError.self) { try LogRules.validate(.activity(activity(child, payload: .diaper(.init(pee: false, poo: false)))), in: snapshot, now: now) }
    }
    @Test func timerExcludesPausesAndSurvivesEncoding() throws {
        var nursing = Nursing(caregiverID: personID)
        nursing.start(.left, at: now)
        nursing.pause(at: now.addingTimeInterval(60))
        nursing.start(.right, at: now.addingTimeInterval(120))
        let restored = try JSONDecoder().decode(Nursing.self, from: JSONEncoder().encode(nursing))
        #expect(restored.duration(at: now.addingTimeInterval(180)) == 120)
        #expect(restored.activeSide == .right)
    }
    @Test func nursingOverlapUsesActiveSegmentsAndNeverMixesChildren() {
        let (_, child) = fixture()
        let sibling = ChildProfile(familyID: familyID, name: "Jamie")
        func session(_ child: ChildProfile, start: Double, end: Double) -> Activity {
            var nursing = Nursing(caregiverID: personID)
            nursing.start(.left, at: now.addingTimeInterval(start))
            nursing.pause(at: now.addingTimeInterval(end)); nursing.finished = true
            return activity(child, payload: .nursing(nursing), date: now.addingTimeInterval(start))
        }
        let first = session(child, start: -120, end: -60)
        let second = session(child, start: -90, end: -30)
        let later = session(child, start: -30, end: 0)
        let otherChild = session(sibling, start: -120, end: 0)
        #expect(LogRules.overlappingNursing(in: [first, second, later, otherChild], childID: child.id, now: now) == [first.id, second.id])
        #expect(LogRules.overlappingNursing(in: [first, later, otherChild], childID: child.id, now: now).isEmpty)
    }
    @Test func concurrentRevisionsRemainVisibleAndDeletionWins() {
        let (_, child) = fixture()
        let initial = RecordRevision(id: UUID(), recordID: child.id, parentIDs: [], value: .child(child), date: now, editorID: personID, deleted: false)
        let edit = RecordRevision(id: UUID(), recordID: child.id, parentIDs: [initial.id], value: .child(child), date: now.addingTimeInterval(2), editorID: personID, deleted: false)
        let deletion = RecordRevision(id: UUID(), recordID: child.id, parentIDs: [initial.id], value: .child(child), date: now.addingTimeInterval(1), editorID: personID, deleted: true)
        let projected = RevisionProjection.project([initial, edit, deletion])
        #expect(projected.count == 1 && projected[0].hasConflict && projected[0].isDeleted)
        let resolution = RecordRevision(id: UUID(), recordID: child.id, parentIDs: [edit.id, deletion.id], value: .child(child), date: now.addingTimeInterval(3), editorID: personID, deleted: true)
        #expect(!RevisionProjection.project([initial, edit, deletion, resolution])[0].hasConflict)
    }
    @Test func calendarBucketsFollowFamilyTimeZoneAcrossDST() {
        let (_, child) = fixture()
        let formatter = ISO8601DateFormatter()
        let end = formatter.date(from: "2026-11-02T17:00:00Z")!
        let first = formatter.date(from: "2026-11-01T05:30:00Z")!
        let second = formatter.date(from: "2026-11-01T06:30:00Z")!
        let entries = [first, second].map { activity(child, payload: .diaper(.init(pee: true, poo: false)), date: $0) }
        let days = LogAnalytics.days(activities: entries, childID: child.id, count: 2, now: end, timeZone: TimeZone(identifier: "America/New_York")!)
        #expect(days[0].summary.wet == 2)
        #expect(days[1].date.timeIntervalSince(days[0].date) == 90000)
        #expect(days[1].isPartial)
    }
    @Test func typedPayloadRoundTripPreservesPrecisionAndFlags() throws {
        let (_, child) = fixture()
        let value = RecordEnvelope(value: .activity(activity(child, payload: .bottle(.init(milkML: VolumeUnit.oz.toML(3), formulaML: 0, unit: .oz)))))
        #expect(try JSONDecoder().decode(RecordEnvelope.self, from: JSONEncoder().encode(value)) == value)
    }
    @Test func optionalGenderPreservesLegacyProfilesAndWidgetCaches() throws {
        let legacy: [String: Any] = ["id": UUID().uuidString, "familyID": familyID.uuidString, "name": "Robin"]
        let child = try JSONDecoder().decode(ChildProfile.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(child.gender == nil)
        let oldWidget: [String: Any] = ["asOf": 0, "children": [legacy.merging(["activities": []]) { _, new in new }]]
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: oldWidget))
        #expect(decoded.children.first?.gender == nil)
        #expect(decoded.children.first?.id == child.id)
        for gender in ChildGender.allCases {
            var updated = child
            updated.gender = gender
            let envelope = RecordEnvelope(value: .child(updated))
            #expect(try JSONDecoder().decode(RecordEnvelope.self, from: JSONEncoder().encode(envelope)) == envelope)
            let cache = CachedChild(id: child.id, familyID: child.familyID, name: child.name, activities: [], gender: gender)
            #expect(try JSONDecoder().decode(CachedChild.self, from: JSONEncoder().encode(cache)) == cache)
        }
    }
}
