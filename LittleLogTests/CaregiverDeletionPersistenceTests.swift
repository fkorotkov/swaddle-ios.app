import Foundation
import Testing

@testable import BabyActivityRecorder

@MainActor
struct CaregiverDeletionPersistenceTests {
    private func setup() throws -> (LogStore, Caregiver) {
        let store = LogStore(
            persistence: PersistenceController(inMemory: true),
            defaults: UserDefaults(suiteName: UUID().uuidString)!, publishesWidgets: false)
        try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml)
        let family = try #require(store.snapshot.family)
        let person = Caregiver(familyID: family.id, name: "Alex", isMother: true)
        try store.save(.caregiver(person))
        return (store, person)
    }

    @Test func deletionSurvivesReloadKeepsRecordsAndRestoresTheSameProfile() throws {
        let (store, person) = try setup()
        let child = try #require(store.selectedChild)
        let pump = PumpSession(
            familyID: person.familyID, motherID: person.id, occurredAt: .now.addingTimeInterval(-60),
            authorID: person.id, source: "Import", totalML: 105, unit: .ml, note: "Original note")
        let bottle = Activity(
            familyID: child.familyID, childID: child.id, occurredAt: .now.addingTimeInterval(-60),
            authorID: person.id, payload: .bottle(Bottle(milkML: 90, formulaML: 0, unit: .ml)))
        try store.save(.pumping(pump))
        try store.save(.activity(bottle))
        let original = try #require(store.history(for: person.id).first)
        try store.deleteCaregiver(person.id)
        let reopened = LogStore(
            persistence: store.persistence, defaults: store.defaults, publishesWidgets: false)
        #expect(!reopened.snapshot.caregivers.contains { $0.id == person.id })
        #expect(reopened.snapshot.pumps == [pump])
        #expect(reopened.snapshot.activities == [bottle])
        #expect(reopened.snapshot.caregiverName(person.id) == "Alex")
        #expect(reopened.snapshot.pumpingHistoryCaregivers.contains { $0.id == person.id })
        #expect(reopened.history(for: pump.id).count == 1)
        #expect(reopened.history(for: bottle.id).count == 1)
        #expect(throws: LogError.self) { try reopened.save(.caregiver(person)) }
        let deleted = try #require(reopened.snapshot.record(person.id))
        try reopened.resolve(deleted, using: original)
        #expect(reopened.snapshot.caregivers.contains(person))
        #expect(reopened.snapshot.pumps == [pump])
        #expect(reopened.snapshot.activities == [bottle])
        #expect(PumpVolumePreset.latest(for: person.id, in: reopened.snapshot)?.session.id == pump.id)
    }

    @Test func staleEditorGenericSaveAndUndoCannotDeleteNewlyLinkedProfile() throws {
        let (store, person) = try setup()
        let stale = try #require(store.snapshot.record(person.id))
        var linked = person
        linked.cloudIdentity = "accepted-account"
        try store.save(.caregiver(linked))
        for attempt in 0..<3 {
            #expect(throws: LogError.self) {
                switch attempt {
                case 0: try store.delete(stale)
                case 1: try store.save(.caregiver(person), deleted: true)
                default: try store.undo()
                }
            }
        }
        #expect(store.snapshot.caregivers.contains(linked))
        #expect(store.history(for: person.id).count == 2)
    }

    @Test func ownerAndCurrentProfileAreProtectedAcrossEntryPoints() throws {
        let (store, person) = try setup()
        let owner = try #require(store.snapshot.record(store.caregiverID))
        #expect(throws: LogError.self) { try store.delete(owner) }
        store.defaults.set(person.id.uuidString, forKey: "caregiverID")
        let target = try #require(store.snapshot.record(person.id))
        #expect(throws: LogError.self) { try store.delete(target) }
        #expect(throws: LogError.self) { try store.save(target.revision.value, deleted: true) }
        #expect(store.snapshot.caregivers.count == 2)
    }

    @Test func deletionUsesFreshNameAndKeepsReservationForRecoveryWithoutReclaimingIt() throws {
        let (store, person) = try setup()
        let stale = try #require(store.snapshot.record(person.id))
        var renamed = person
        renamed.name = "Alex old"
        renamed.invitation = CaregiverInvitation(
            shareRecordName: "share", participantID: "member", accountIdentity: nil)
        try store.save(.caregiver(renamed))
        try store.delete(stale)
        #expect(store.snapshot.caregiverName(person.id) == "Alex old")
        let deleted = try #require(store.snapshot.record(person.id))
        #expect(deleted.revision.value == .caregiver(renamed))
        let accepted = AcceptedCaregiverIdentity(
            shareRecordName: "share", participantID: "member", accountIdentity: "account")
        #expect(
            try CaregiverInvitationRules.profile(
                for: "account", participant: accepted, in: store.snapshot) == nil)
        let count = store.history(for: person.id).count
        try store.deleteCaregiver(person.id)
        #expect(store.history(for: person.id).count == count)
    }

    @Test func restorationRevalidatesInvitationAndOnlyOwnerCanRestore() throws {
        let (store, person) = try setup()
        let original = try #require(store.history(for: person.id).first)
        let invitation = CaregiverInvitation(
            shareRecordName: "share", participantID: "member", accountIdentity: "account")
        _ = try store.reserveCaregiverInvitation(person.id, invitation: invitation)
        let reserved = try #require(store.history(for: person.id).first { $0.id != original.id })
        try store.deleteCaregiver(person.id)
        let other = Caregiver(
            familyID: person.familyID, name: "Alex linked", isMother: true, cloudIdentity: "account")
        try store.save(.caregiver(other))
        let deleted = try #require(store.snapshot.record(person.id))
        #expect(throws: LogError.self) { try store.resolve(deleted, using: reserved) }
        let ownerID = store.caregiverID
        store.defaults.set(other.id.uuidString, forKey: "caregiverID")
        #expect(throws: LogError.self) { try store.resolve(deleted, using: original) }
        store.defaults.set(ownerID.uuidString, forKey: "caregiverID")
        try store.resolve(deleted, using: original)
        #expect(store.snapshot.caregivers.contains(person))
        #expect(store.snapshot.caregivers.contains(other))
    }
}
