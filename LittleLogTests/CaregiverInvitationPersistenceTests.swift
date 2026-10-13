import Foundation
import CloudKit
import Testing
@testable import BabyActivityRecorder

@MainActor
struct CaregiverInvitationPersistenceTests {
    private func store() -> LogStore {
        LogStore(persistence: PersistenceController(inMemory: true), defaults: UserDefaults(suiteName: UUID().uuidString)!, publishesWidgets: false)
    }

    @Test func invitationAndAcceptancePreservePumpingIdentityAndRecordedBy() throws {
        let store = store()
        try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml)
        let family = try #require(store.snapshot.family)
        let ownerID = store.caregiverID
        let mother = Caregiver(familyID: family.id, name: "Alex", isMother: true)
        try store.save(.caregiver(mother))
        let pump = PumpSession(familyID: family.id, motherID: mother.id, occurredAt: .now, authorID: ownerID, totalML: 105, unit: .ml)
        try store.save(.pumping(pump))
        let invitation = CaregiverInvitation(shareRecordName: "share", participantID: "participant", accountIdentity: nil)
        _ = try store.reserveCaregiverInvitation(mother.id, invitation: invitation)
        let count = store.history(for: mother.id).count
        _ = try store.reserveCaregiverInvitation(mother.id, invitation: invitation)
        #expect(store.history(for: mother.id).count == count)

        store.defaults.set(UUID().uuidString, forKey: "caregiverID")
        let accepted = AcceptedCaregiverIdentity(shareRecordName: "share", participantID: "participant", accountIdentity: "alex-account")
        #expect(try store.adoptCaregiverIdentity(account: "alex-account", participant: accepted))
        store.reload()
        #expect(store.caregiverID == mother.id)
        #expect(store.snapshot.caregivers.count == 2)
        #expect(store.snapshot.pumps == [pump])
        #expect(store.snapshot.pumps.first?.authorID == ownerID)
        #expect(store.snapshot.pumps.first?.motherID == mother.id)
        #expect(store.snapshot.caregivers.first { $0.id == mother.id }?.cloudIdentity == "alex-account")
        let claimRevision = try #require(store.history(for: mother.id).first { revision in
            if case .caregiver(let person) = revision.value { return person.cloudIdentity == "alex-account" }
            return false
        })
        #expect(claimRevision.editorID == mother.id)
        #expect(try !store.adoptCaregiverIdentity(account: "alex-account", participant: accepted))

        // An already visible generic join form must not create a duplicate after
        // a delayed import links the pre-existing profile.
        try store.createJoinedCaregiver(name: "Alex again", pumping: true)
        #expect(store.snapshot.caregivers.count == 2)
        #expect(store.snapshot.caregivers.first { $0.id == mother.id }?.name == "Alex")
    }

    @Test func nonOwnerReservationFailsWithoutChangingAnyProfile() throws {
        let store = store()
        try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml)
        let family = try #require(store.snapshot.family)
        let mother = Caregiver(familyID: family.id, name: "Alex", isMother: true)
        try store.save(.caregiver(mother))
        store.defaults.set(UUID().uuidString, forKey: "caregiverID")
        #expect(throws: LogError.self) {
            try store.reserveCaregiverInvitation(mother.id, invitation: .init(shareRecordName: "share", participantID: "participant", accountIdentity: nil))
        }
        #expect(store.snapshot.caregivers.first { $0.id == mother.id } == mother)
        #expect(store.history(for: mother.id).count == 1)
    }

    @Test func cloudKitVerifiedAliasPreservesExistingProfileAndPumpingHistory() throws {
        let store = store()
        try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml)
        let family = try #require(store.snapshot.family)
        let ownerID = store.caregiverID
        let mother = Caregiver(familyID: family.id, name: "Alex", isMother: true)
        try store.save(.caregiver(mother))
        let pump = PumpSession(familyID: family.id, motherID: mother.id, occurredAt: .now, authorID: ownerID, totalML: 95, unit: .ml)
        try store.save(.pumping(pump))
        _ = try store.reserveCaregiverInvitation(mother.id, invitation: .init(shareRecordName: "share", participantID: "participant",
                                                                          accountIdentity: "participant-record"))
        store.defaults.set(UUID().uuidString, forKey: "caregiverID")
        let accepted = AcceptedCaregiverIdentity(shareRecordName: "share", participantID: "participant",
                                                accountIdentity: "canonical-account", participantAccountIdentity: "participant-record")
        #expect(try store.adoptCaregiverIdentity(account: "canonical-account", participant: accepted))
        store.reload()
        #expect(store.caregiverID == mother.id)
        #expect(store.snapshot.pumps == [pump])
        #expect(store.snapshot.caregivers.count == 2)
        // After relaunch, the persisted canonical link still works without
        // replaying the network verification or rewriting the profile.
        #expect(try !store.adoptCaregiverIdentity(account: "canonical-account", participant: nil))
    }

    @Test func serverCurrentUserAliasLinksTheReservedProfileWithoutDuplicatingHistory() throws {
        let store = store()
        try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml)
        let family = try #require(store.snapshot.family)
        let ownerID = store.caregiverID
        let person = Caregiver(familyID: family.id, name: "Alex", isMother: true)
        try store.save(.caregiver(person))
        let pump = PumpSession(familyID: family.id, motherID: person.id, occurredAt: .now, authorID: ownerID, totalML: 120, unit: .ml)
        try store.save(.pumping(pump))
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: .init(zoneName: "family", ownerName: "owner"))
        _ = try store.reserveCaregiverInvitation(person.id, invitation: .init(shareRecordName: shareID.recordName,
                                                    participantID: "invited-member", accountIdentity: "owner-visible-record"))
        let member = CloudInvitationSnapshot.Participant(id: "invited-member", accountIdentity: nil,
            membership: .init(status: .accepted, role: .privateUser, permission: .readWrite), usesCurrentUserAlias: true)
        let cloud = CloudInvitationSnapshot(recordID: shareID, currentParticipant: member, participants: [member])
        let accepted = try cloud.verifyingCurrentParticipant(account: "canonical-account").acceptedIdentity(account: "canonical-account")
        store.defaults.set(UUID().uuidString, forKey: "caregiverID")
        #expect(try store.adoptCaregiverIdentity(account: "canonical-account", participant: accepted))
        store.reload()
        #expect(store.caregiverID == person.id)
        #expect(store.snapshot.caregivers.count == 2)
        #expect(store.snapshot.pumps == [pump])
        #expect(try !store.adoptCaregiverIdentity(account: "canonical-account", participant: nil))
        try store.createJoinedCaregiver(name: "Unwanted duplicate", pumping: true)
        #expect(store.snapshot.caregivers.count == 2)
    }
}
