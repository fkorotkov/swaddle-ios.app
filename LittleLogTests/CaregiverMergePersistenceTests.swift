import Foundation
import Testing

@testable import BabyActivityRecorder

@MainActor
struct CaregiverMergePersistenceTests {
    private func setup() throws -> (LogStore, Caregiver, Caregiver) {
        let store = LogStore(
            persistence: PersistenceController(inMemory: true),
            defaults: UserDefaults(suiteName: UUID().uuidString)!, publishesWidgets: false)
        try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml)
        let family = try #require(store.snapshot.family)
        let duplicate = Caregiver(familyID: family.id, name: "Alex old", isMother: true)
        let kept = Caregiver(familyID: family.id, name: "Alex", cloudIdentity: "alex-account")
        try store.save(.caregiver(duplicate))
        try store.save(.caregiver(kept))
        return (store, duplicate, kept)
    }

    private func plan(_ store: LogStore, _ duplicate: Caregiver, _ kept: Caregiver) throws
        -> CaregiverMergePlan
    {
        try CaregiverMergeRules.plan(
            sourceID: duplicate.id, destinationID: kept.id,
            in: store.snapshot, actorID: store.caregiverID, canEdit: store.canEdit)
    }

    @Test func mergingAndSeparatingSurviveReloadPreserveEditedHistoryAndNewEntries() throws {
        let (store, duplicate, kept) = try setup()
        let session = PumpSession(
            familyID: duplicate.familyID, motherID: duplicate.id,
            occurredAt: .now.addingTimeInterval(-600), authorID: duplicate.id,
            source: "Import", totalML: 105, leftML: 60, rightML: 45, unit: .ml,
            note: "Original note", importIdentity: ImportIdentity(source: "archive", id: "pump-1"))
        try store.save(.pumping(session))
        let child = try #require(store.selectedChild)
        let bottle = Activity(
            familyID: child.familyID, childID: child.id, occurredAt: .now.addingTimeInterval(-60),
            authorID: store.caregiverID,
            payload: .bottle(Bottle(milkML: 90, formulaML: 30, unit: .ml)))
        try store.save(.activity(bottle), rememberBottle: true)
        let bottleDefault = store.previousBottle(childID: child.id)
        try store.mergeCaregivers(plan(store, duplicate, kept))
        #expect(store.history(for: session.id).count == 1)
        #expect(store.undoID == nil)
        #expect(store.snapshot.pumps.first?.motherID == kept.id)
        #expect(store.snapshot.pumps.first?.authorID == duplicate.id)
        #expect(store.previousBottle(childID: child.id) == bottleDefault)
        #expect(store.snapshot.activities == [bottle])
        #expect(PumpVolumePreset.latest(for: kept.id, in: store.snapshot)?.session.totalML == 105)
        var edit = try #require(store.snapshot.pumps.first)
        edit.note = "Edited after merge"
        try store.save(.pumping(edit))
        var new = session
        new.id = UUID()
        new.importIdentity = nil
        new.authorID = store.caregiverID
        try store.save(.pumping(new))
        let reopened = LogStore(
            persistence: store.persistence, defaults: store.defaults, publishesWidgets: false)
        #expect(reopened.snapshot.pumps.allSatisfy { $0.motherID == kept.id })
        try reopened.separateCaregiver(duplicate.id)
        #expect(reopened.snapshot.pumps.first { $0.id == session.id }?.motherID == duplicate.id)
        #expect(reopened.snapshot.pumps.first { $0.id == session.id }?.note == "Edited after merge")
        #expect(reopened.snapshot.pumps.first { $0.id == session.id }?.authorID == duplicate.id)
        #expect(reopened.snapshot.pumps.first { $0.id == new.id }?.motherID == kept.id)
        #expect(reopened.snapshot.pumps.reduce(Decimal(0)) { $0 + $1.totalML } == 210)
        #expect(
            reopened.snapshot.caregivers.first { $0.id == kept.id }?.cloudIdentity == "alex-account"
        )
    }

    @Test func staleConfirmationCannotDiscardProfileRenameOrAccountAcceptance() throws {
        let (store, duplicate, kept) = try setup()
        let reviewed = try plan(store, duplicate, kept)
        var renamed = kept
        renamed.name = "New name"
        try store.save(.caregiver(renamed))
        let sourceCount = store.history(for: duplicate.id).count
        #expect(throws: LogError.self) { try store.mergeCaregivers(reviewed) }
        #expect(store.history(for: duplicate.id).count == sourceCount)
        let fresh = try plan(store, duplicate, renamed)
        var linked = duplicate
        linked.cloudIdentity = "late-account"
        try store.save(.caregiver(linked))
        #expect(throws: LogError.self) { try store.mergeCaregivers(fresh) }
        #expect(store.snapshot.caregivers.contains(linked))
        #expect(store.snapshot.caregivers.contains(renamed))
    }

    @Test func rawAliasWritesAndNonOwnerMergeOrSeparationAreRejected() throws {
        let (store, duplicate, kept) = try setup()
        var forged = duplicate
        forged.mergedIntoID = kept.id
        #expect(throws: LogError.self) { try store.save(.caregiver(forged), deleted: true) }
        let reviewed = try plan(store, duplicate, kept)
        let owner = store.caregiverID
        store.defaults.set(kept.id.uuidString, forKey: "caregiverID")
        #expect(throws: LogError.self) { try store.mergeCaregivers(reviewed) }
        store.defaults.set(owner.uuidString, forKey: "caregiverID")
        try store.mergeCaregivers(reviewed)
        store.defaults.set(kept.id.uuidString, forKey: "caregiverID")
        #expect(throws: LogError.self) { try store.separateCaregiver(duplicate.id) }
        let original = try #require(store.history(for: duplicate.id).first { !$0.deleted })
        let deleted = try #require(store.snapshot.record(duplicate.id))
        #expect(throws: LogError.self) { try store.resolve(deleted, using: original) }
        #expect(store.snapshot.record(duplicate.id)?.isDeleted == true)
    }

    @Test func stalePumpImportUsesKeptProfileAndChecksCombinedImportIdentities() throws {
        let (store, duplicate, kept) = try setup()
        let session = PumpSession(
            familyID: duplicate.familyID, motherID: duplicate.id,
            occurredAt: .now.addingTimeInterval(-60), authorID: store.caregiverID,
            totalML: 90, unit: .ml, importIdentity: ImportIdentity(source: "archive", id: "pump-1"))
        try store.save(.pumping(session))
        try store.mergeCaregivers(plan(store, duplicate, kept))
        var repeated = session
        repeated.id = UUID()
        #expect(throws: LogError.self) { try store.importPumpingSessions([repeated]) }
        var pending = repeated
        pending.importIdentity?.id = "pump-2"
        #expect(try store.importPumpingSessions([pending]) == 1)
        #expect(try store.importPumpingSessions([pending]) == 0)
        #expect(store.snapshot.pumps.count == 2)
        try store.separateCaregiver(duplicate.id)
        #expect(store.snapshot.pumps.first { $0.id == pending.id }?.motherID == kept.id)
    }

    @Test func separatingDoesNotReclaimTheKeptAccountsInvitation() throws {
        let (store, duplicate, kept) = try setup()
        var reserved = duplicate
        reserved.invitation = CaregiverInvitation(
            shareRecordName: "share", participantID: "alex", accountIdentity: kept.cloudIdentity)
        try store.save(.caregiver(reserved))
        try store.mergeCaregivers(plan(store, reserved, kept))
        try store.separateCaregiver(reserved.id)
        let restored = try #require(store.snapshot.caregivers.first { $0.id == reserved.id })
        #expect(restored.invitation == nil)
        #expect(restored.cloudIdentity == nil)
        #expect(
            try CaregiverInvitationRules.profile(
                for: "alex-account", participant: nil, in: store.snapshot)?.id == kept.id)
    }
}
