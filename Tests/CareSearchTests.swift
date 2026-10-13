import Foundation
import Testing
@testable import LittleLogCore

struct CareSearchTests {
    let fixture = LogRulesTests()
    func append(_ value: RecordValue, to snapshot: inout FamilySnapshot, deleted: Bool = false) {
        let revision = RecordRevision(id: UUID(), recordID: value.id, parentIDs: [], value: value, date: fixture.now, editorID: fixture.personID, deleted: deleted)
        snapshot.records.append(ProjectedRecord(revision: revision, heads: [revision]))
    }
    @Test func stableIDsRequireTheExactFamilyAndRecord() throws {
        var (snapshot, child) = fixture.fixture()
        let activity = fixture.activity(child, payload: .bottle(Bottle(milkML: 90, formulaML: 30, unit: .ml)))
        append(.activity(activity), to: &snapshot)
        let key = CareContentID(familyID: child.familyID, recordID: activity.id)
        #expect(CareContentID(key.rawValue) == key)
        #expect(try CareSearchCatalog.resolve(key.rawValue, in: snapshot).key.recordID == activity.id)
        #expect(throws: LogError.self) { try CareSearchCatalog.resolve(CareContentID(familyID: UUID(), recordID: activity.id).rawValue, in: snapshot) }
        for malformed in ["", key.rawValue + "/", activity.id.uuidString, "/" + key.rawValue] { #expect(CareContentID(malformed) == nil) }
    }
    @Test func notesStayNotesAndImportedBookkeepingStaysPrivate() throws {
        var (snapshot, child) = fixture.fixture()
        var note = fixture.activity(child, payload: .careNote)
        note.note = "Red marks on cheeks\n\nOriginal JSON:\n{\"private_source_id\":\"123\"}"
        append(.activity(note), to: &snapshot)
        let bottle = fixture.activity(child, payload: .bottle(Bottle(milkML: 60, formulaML: 15, unit: .ml)))
        append(.activity(bottle), to: &snapshot)
        let documents = CareSearchCatalog.documents(in: snapshot)
        #expect(documents.filter(\.isCareNote).count == 1)
        let result = try #require(documents.first(where: { $0.isCareNote }))
        #expect(result.content.contains("Red marks on cheeks"))
        #expect(!result.content.contains("private_source_id"))
        #expect(snapshot.activities.first(where: { $0.id == note.id })?.note == note.note)
        #expect(documents.first(where: { $0.key.recordID == bottle.id })?.content.contains("75 mL total") == true)
    }
    @Test func deletedConflictingAndIncompleteRecordsAreNotDiscoverable() {
        var (snapshot, child) = fixture.fixture()
        let first = fixture.activity(child, payload: .careNote)
        append(.activity(first), to: &snapshot, deleted: true)
        let conflicted = fixture.activity(child, payload: .bottle(Bottle(milkML: 60, formulaML: 0, unit: .ml)))
        append(.activity(conflicted), to: &snapshot)
        var otherHead = snapshot.records.last!.revision
        otherHead.id = UUID()
        snapshot.records[snapshot.records.count - 1].heads.append(otherHead)
        var nursing = Nursing(caregiverID: fixture.personID)
        nursing.start(.left, at: fixture.now)
        append(.activity(fixture.activity(child, payload: .nursing(nursing))), to: &snapshot)
        #expect(CareSearchCatalog.documents(in: snapshot).isEmpty)
    }
    @Test func deletedChildOrPumpingCaregiverRemovesTheirContent() {
        var (snapshot, child) = fixture.fixture()
        append(.activity(fixture.activity(child, payload: .bottle(Bottle(milkML: 60, formulaML: 0, unit: .ml)))), to: &snapshot)
        append(.pumping(PumpSession(familyID: child.familyID, motherID: fixture.personID, occurredAt: fixture.now, authorID: fixture.personID, totalML: 105, unit: .ml)), to: &snapshot)
        #expect(CareSearchCatalog.documents(in: snapshot).count == 2)
        snapshot.records.removeAll { $0.id == child.id }
        let remaining = CareSearchCatalog.documents(in: snapshot)
        #expect(remaining.count == 1 && remaining.first?.content.contains("separate from bottle intake") == true)
        snapshot.records.removeAll { $0.id == fixture.personID }
        #expect(CareSearchCatalog.documents(in: snapshot).isEmpty)
    }
    @Test func renamedChildAndEditedNotesReplaceOldSearchText() throws {
        var (snapshot, child) = fixture.fixture()
        var note = fixture.activity(child, payload: .careNote)
        note.note = "Cheeks looked red"
        append(.activity(note), to: &snapshot)
        let id = CareSearchCatalog.documents(in: snapshot)[0].id
        child.name = "Léon"
        snapshot.records.removeAll { $0.id == child.id || $0.id == note.id }
        append(.child(child), to: &snapshot)
        note.note = "Cheeks looked clear"
        append(.activity(note), to: &snapshot)
        let documents = CareSearchCatalog.documents(in: snapshot)
        #expect(documents[0].id == id)
        #expect(CareSearchCatalog.matching("leon clear", documents: documents).count == 1)
        #expect(CareSearchCatalog.matching("red", documents: documents).isEmpty)
        #expect(CareSearchCatalog.matching("Robin", documents: documents).isEmpty)
        #expect(CareSearchCatalog.matching("", documents: documents, limit: 0).isEmpty)
    }
    @Test func reportIDsRecalculateAtReadTimeAndRejectDeletedChildren() throws {
        var (snapshot, child) = fixture.fixture()
        let key = FeedingReportID(familyID: child.familyID, childID: child.id, period: .last24Hours)
        let bottle = fixture.activity(child, payload: .bottle(Bottle(milkML: 0, formulaML: 0, unit: .ml, unclassifiedML: 95)), date: fixture.now.addingTimeInterval(-86390))
        append(.activity(bottle), to: &snapshot)
        #expect(FeedingReportID(key.rawValue) == key)
        #expect(try key.report(in: snapshot, now: fixture.now).summary.totalML == 95)
        #expect(try key.report(in: snapshot, now: fixture.now.addingTimeInterval(11)).summary.totalML == 0)
        #expect(throws: LogError.self) { try FeedingReportID(familyID: UUID(), childID: child.id, period: .last24Hours).report(in: snapshot, now: fixture.now) }
        snapshot.records.removeAll { $0.id == child.id }
        #expect(throws: LogError.self) { try key.report(in: snapshot, now: fixture.now) }
    }

    @Test func onscreenSubsetKeepsFullRosterAndPrivacyRules() throws {
        var (snapshot, child) = fixture.fixture()
        let bottle = fixture.activity(
            child, payload: .bottle(Bottle(milkML: 90, formulaML: 30, unit: .ml)))
        let pump = PumpSession(
            familyID: child.familyID, motherID: fixture.personID,
            occurredAt: fixture.now, authorID: fixture.personID, totalML: 150, unit: .ml)
        let deleted = fixture.activity(child, payload: .careNote)
        append(.activity(bottle), to: &snapshot)
        append(.pumping(pump), to: &snapshot)
        append(.activity(deleted), to: &snapshot, deleted: true)
        append(
            .activity(fixture.activity(child, payload: .diaper(Diaper(pee: true, poo: false)))),
            to: &snapshot)
        let requested = Set([bottle.id, pump.id, deleted.id, UUID()])
        let full = CareSearchCatalog.documents(in: snapshot)
        let subset = CareSearchCatalog.documents(in: snapshot, recordIDs: requested)
        #expect(subset == full.filter { requested.contains($0.key.recordID) })
        #expect(subset.count == 2)
        #expect(subset.contains { $0.caregiverID == fixture.personID })
        #expect(CareSearchCatalog.documents(in: snapshot, recordIDs: []).isEmpty)

        // A conflict in a related child that is outside the requested subset
        // must still prevent exposing its care entry to onscreen discovery.
        let childIndex = try #require(snapshot.records.firstIndex { $0.id == child.id })
        var competing = snapshot.records[childIndex].revision
        competing.id = UUID()
        snapshot.records[childIndex].heads.append(competing)
        #expect(CareSearchCatalog.documents(in: snapshot, recordIDs: [bottle.id]).isEmpty)
    }
}
