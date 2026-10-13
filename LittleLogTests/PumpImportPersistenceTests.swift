import Foundation
import Testing
@testable import BabyActivityRecorder

@MainActor
struct PumpImportPersistenceTests {
    func setup() throws -> (LogStore, Caregiver) {
        let store = LogStore(persistence: PersistenceController(inMemory: true), defaults: UserDefaults(suiteName: UUID().uuidString)!, publishesWidgets: false)
        try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml)
        let family = try #require(store.snapshot.family)
        let mother = Caregiver(familyID: family.id, name: "Alex", isMother: true)
        try store.save(.caregiver(mother))
        return (store, mother)
    }
    func sessions(_ store: LogStore, _ mother: Caregiver) throws -> [PumpSession] {
        try JSONLinesPumpImport.parse(JSONLinesPumpImport.example.replacingOccurrences(of: #""totalML":105"#, with: #""totalML":null"#) + "\n" + JSONLinesPumpImport.totalOnlyExample)
            .map { try $0.session(mother: mother, authorID: store.caregiverID) }
    }

    @Test(arguments: [false, true])
    func nonPumpingCaregiverCanRecordForPumpingProfile(asParticipant: Bool) throws {
        let (store, mother) = try setup()
        if asParticipant {
            let helper = Caregiver(familyID: mother.familyID, name: "Jamie", isMother: false)
            try store.save(.caregiver(helper))
            store.defaults.set(helper.id.uuidString, forKey: "caregiverID")
            store.reload()
            #expect(!store.isOwner)
        }
        let author = try #require(store.snapshot.caregivers.first { $0.id == store.caregiverID })
        #expect(!author.isMother && store.canEdit)
        let target = try LogRules.mother(nil, in: store.snapshot)
        #expect(target.id == mother.id && target.id != author.id)

        let session = PumpSession(
            familyID: mother.familyID, motherID: target.id,
            occurredAt: .now, authorID: author.id, totalML: 105, unit: .ml)
        try store.save(.pumping(session))
        store.reload()
        #expect(store.snapshot.pumps == [session])
        #expect(store.snapshot.recentCare(for: try #require(store.selectedChild).id) == [.pumping(session)])
        #expect(PumpVolumePreset.latest(for: target.id, in: store.snapshot)?.session.id == session.id)
        #expect(PumpVolumePreset.latest(for: author.id, in: store.snapshot) == nil)

        var correction = session
        correction.totalML = 120
        try store.save(.pumping(correction))
        #expect(store.snapshot.pumps == [correction])
        #expect(store.history(for: session.id).allSatisfy { $0.editorID == author.id })
        #expect(store.snapshot.caregivers.first { $0.id == author.id }?.isMother == false)

        var wrongTarget = session
        wrongTarget.id = UUID()
        wrongTarget.motherID = author.id
        #expect(throws: LogError.self) { try store.save(.pumping(wrongTarget)) }
        #expect(store.snapshot.pumps == [correction])
    }

    @Test func bulkPumpImportPersistsMetadataAndUndoLeavesFeedingUntouched() throws {
        let (store, mother) = try setup()
        let child = try #require(store.selectedChild)
        let bottle = Bottle(milkML: 90, formulaML: 15, unit: .ml)
        try store.save(.activity(Activity(familyID: child.familyID, childID: child.id, occurredAt: .now, authorID: store.caregiverID, payload: .bottle(bottle))), rememberBottle: true)
        let imported = try sessions(store, mother)
        #expect(try store.importPumpingSessions(imported) == 2)
        store.reload()
        #expect(store.snapshot.pumps.count == 2)
        let stored = try #require(store.snapshot.pumps.first { $0.id == imported[0].id })
        #expect(stored == imported[0])
        #expect(stored.motherID == mother.id && stored.authorID == store.caregiverID)
        #expect(stored.note.contains("Original JSON:") && stored.importIdentity?.id == "pump-123")
        #expect(stored.timeZoneIdentifier != nil)
        #expect(store.previousBottle(childID: child.id) == bottle)
        #expect(ActivitySummary(activities: store.snapshot.activities, childID: child.id).totalML == 105)
        #expect(try store.importPumpingSessions(imported) == 0)
        try store.undo()
        #expect(store.snapshot.pumps.isEmpty && store.snapshot.activities.count == 1)
        #expect(store.previousBottle(childID: child.id) == bottle)
        #expect(try store.importPumpingSessions(sessions(store, mother)) == 2)
    }

    @Test func invalidBatchNeverSavesAnyRows() throws {
        let (store, mother) = try setup()
        let valid = try sessions(store, mother)
        for kind in 0..<5 {
            var invalid = valid
            switch kind {
            case 0: invalid[1].totalML = -1
            case 1: invalid[1].motherID = UUID()
            case 2: invalid[1].familyID = UUID()
            case 3: invalid[1].authorID = UUID()
            default: invalid[1].importIdentity = invalid[0].importIdentity
            }
            #expect(throws: LogError.self) { try store.importPumpingSessions(invalid) }
            #expect(store.snapshot.pumps.isEmpty)
        }
        try store.delete(try #require(store.snapshot.record(mother.id)))
        #expect(throws: LogError.self) { try store.importPumpingSessions(valid) }
        #expect(store.snapshot.pumps.isEmpty)
    }

    @Test func sourceIDsRecheckedBeforeSaveAndScopedToPumpingCaregiver() throws {
        let (store, mother) = try setup()
        let imported = try sessions(store, mother)
        #expect(try store.importPumpingSessions(imported) == 2)
        var reimport = try sessions(store, mother)
        reimport[0].minutes = 20
        #expect(throws: LogError.self) { try store.importPumpingSessions(Array(reimport.reversed())) }
        #expect(store.snapshot.pumps.count == 2)
        #expect(store.snapshot.pumps.first { $0.id == imported[0].id }?.minutes == 15)
        let another = Caregiver(familyID: mother.familyID, name: "Jamie", isMother: true)
        try store.save(.caregiver(another))
        #expect(try store.importPumpingSessions(sessions(store, another)) == 2)
        #expect(store.snapshot.pumps.count == 4)
        let noChild = try #require(store.selectedChild).id
        try store.delete(try #require(store.snapshot.record(noChild)))
        let draft = try JSONLinesPumpImport.parse(JSONLinesPumpImport.totalOnlyExample)[0]
        #expect(try store.importPumpingSessions([draft.session(mother: mother, authorID: store.caregiverID)]) == 1)
    }

    @Test func pumpingVolumePresetFollowsSavedSessionsAndUndoWithoutWritingADraft() throws {
        let (store, mother) = try setup()
        let first = PumpSession(familyID: mother.familyID, motherID: mother.id,
                                occurredAt: .now.addingTimeInterval(-3600), authorID: store.caregiverID,
                                totalML: 105, leftML: 60, rightML: 45, unit: .ml, minutes: 20, note: "Previous note")
        try store.save(.pumping(first))
        let previous = try #require(PumpVolumePreset.latest(for: mother.id, in: store.snapshot))
        var draft = previous.draft(unit: .oz)
        draft.adjust(1, component: .first)
        store.reload()
        // Adjusting or cancelling the editor never changes saved history or the next preset.
        #expect(store.snapshot.pumps == [first])
        #expect(PumpVolumePreset.latest(for: mother.id, in: store.snapshot)?.session.totalML == 105)

        let values = try draft.validated()
        let next = PumpSession(familyID: mother.familyID, motherID: mother.id,
                               occurredAt: .now, authorID: store.caregiverID, totalML: values.0 + values.1,
                               leftML: values.0, rightML: values.1, unit: draft.unit)
        try store.save(.pumping(next))
        #expect(PumpVolumePreset.latest(for: mother.id, in: store.snapshot)?.session.id == next.id)
        #expect(next.minutes == nil && next.note.isEmpty && next.id != first.id)
        try store.undo()
        #expect(PumpVolumePreset.latest(for: mother.id, in: store.snapshot)?.session.id == first.id)
        try store.delete(try #require(store.snapshot.record(first.id)))
        #expect(PumpVolumePreset.latest(for: mother.id, in: store.snapshot) == nil)
    }
}
