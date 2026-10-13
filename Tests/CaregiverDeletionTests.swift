import Foundation
import Testing

@testable import LittleLogCore

struct CaregiverDeletionTests {
    private let fixture = LogRulesTests()

    private func state(linked: String? = nil, invitation: CaregiverInvitation? = nil) -> (
        FamilySnapshot, Caregiver
    ) {
        var (snapshot, _) = fixture.fixture()
        let person = Caregiver(
            familyID: fixture.familyID, name: "Alex", isMother: true,
            cloudIdentity: linked, invitation: invitation)
        append(.caregiver(person), to: &snapshot)
        return (snapshot, person)
    }

    private func append(
        _ value: RecordValue, to snapshot: inout FamilySnapshot, deleted: Bool = false
    ) {
        let revision = RecordRevision(
            id: UUID(), recordID: value.id, parentIDs: [], value: value,
            date: fixture.now, editorID: fixture.personID, deleted: deleted)
        snapshot.records.append(ProjectedRecord(revision: revision, heads: [revision]))
    }

    @Test func onlyEditingOwnerCanDeleteAnotherProfile() throws {
        let (snapshot, person) = state()
        #expect(
            try CaregiverDeletionRules.validate(
                person.id, in: snapshot, actorID: fixture.personID, canEdit: true) == person)
        for actor in [person.id, UUID()] {
            #expect(throws: LogError.self) {
                try CaregiverDeletionRules.validate(person.id, in: snapshot, actorID: actor, canEdit: true)
            }
        }
        #expect(throws: LogError.self) {
            try CaregiverDeletionRules.validate(
                person.id, in: snapshot, actorID: fixture.personID, canEdit: false)
        }
        #expect(throws: LogError.self) {
            try CaregiverDeletionRules.validate(
                fixture.personID, in: snapshot, actorID: fixture.personID, canEdit: true)
        }
    }

    @Test func pendingReservationCanBeDeletedButLinkedAccountCannot() throws {
        let invitation = CaregiverInvitation(
            shareRecordName: "share", participantID: "member", accountIdentity: "account")
        let (pending, person) = state(invitation: invitation)
        #expect(
            try CaregiverDeletionRules.validate(
                person.id, in: pending, actorID: fixture.personID, canEdit: true
            ).invitation == invitation)
        let (linked, active) = state(linked: "account", invitation: invitation)
        #expect(throws: LogError.self) {
            try CaregiverDeletionRules.validate(
                active.id, in: linked, actorID: fixture.personID, canEdit: true)
        }
    }

    @Test func concurrentAccountLinkCannotBeDiscardedEvenWhenKeepingDeletion() throws {
        var (snapshot, person) = state()
        let index = try #require(snapshot.records.firstIndex { $0.id == person.id })
        var linked = person
        linked.cloudIdentity = "account"
        let branch = RecordRevision(
            id: UUID(), recordID: person.id, parentIDs: [], value: .caregiver(linked),
            date: fixture.now.addingTimeInterval(-60), editorID: person.id, deleted: false)
        snapshot.records[index].heads.append(branch)
        #expect(throws: LogError.self) {
            try CaregiverDeletionRules.validate(
                person.id, in: snapshot, actorID: fixture.personID,
                canEdit: true, resolvingDeletion: true)
        }
    }

    @Test func runningNursingMustFinishBeforeProfileDeletion() throws {
        var (snapshot, person) = state()
        let child = try #require(snapshot.children.first)
        var nursing = Nursing(caregiverID: person.id)
        nursing.start(.left, at: fixture.now.addingTimeInterval(-60))
        append(.activity(fixture.activity(child, payload: .nursing(nursing))), to: &snapshot)
        #expect(throws: LogError.self) {
            try CaregiverDeletionRules.validate(
                person.id, in: snapshot, actorID: fixture.personID, canEdit: true)
        }
    }

    @Test func offlineDeletionCannotHideAConcurrentAccountLinkAfterSync() throws {
        let (snapshot, person) = state()
        let original = try #require(snapshot.record(person.id)?.revision)
        var linkedPerson = person
        linkedPerson.cloudIdentity = "accepted-account"
        let linked = RecordRevision(
            id: UUID(), recordID: person.id, parentIDs: [original.id], value: .caregiver(linkedPerson),
            date: fixture.now.addingTimeInterval(1), editorID: person.id, deleted: false)
        let deletion = RecordRevision(
            id: UUID(), recordID: person.id, parentIDs: [original.id], value: .caregiver(person),
            date: fixture.now.addingTimeInterval(2), editorID: fixture.personID, deleted: true)
        for revisions in [[original, linked, deletion], [deletion, original, linked], [linked, deletion, original]] {
            let merged = try #require(RevisionProjection.project(revisions).first)
            #expect(merged.hasConflict && !merged.isDeleted)
            #expect(merged.revision.value == .caregiver(linkedPerson))
            var synced = snapshot
            synced.records.removeAll { $0.id == person.id }
            synced.records.append(merged)
            #expect(synced.caregivers.contains(linkedPerson))
            #expect(throws: LogError.self) {
                try CaregiverDeletionRules.validate(
                    person.id, in: synced, actorID: fixture.personID, canEdit: true, resolvingDeletion: true)
            }
        }
        let resolved = RecordRevision(
            id: UUID(), recordID: person.id, parentIDs: [linked.id, deletion.id], value: .caregiver(linkedPerson),
            date: fixture.now.addingTimeInterval(3), editorID: fixture.personID, deleted: false)
        let merged = try #require(RevisionProjection.project([original, linked, deletion, resolved]).first)
        #expect(!merged.hasConflict && !merged.isDeleted)
        #expect(merged.revision.value == .caregiver(linkedPerson))
    }

    @Test func deletedProfileKeepsNamesPumpingAnalyticsAndSearchButCannotRecord() throws {
        var (snapshot, person) = state()
        let child = try #require(snapshot.children.first)
        let pump = PumpSession(
            familyID: child.familyID, motherID: person.id, occurredAt: fixture.now,
            authorID: person.id, totalML: 105, unit: .ml)
        append(.pumping(pump), to: &snapshot)
        let index = try #require(snapshot.records.firstIndex { $0.id == person.id })
        snapshot.records[index].revision.deleted = true
        snapshot.records[index].heads[0].deleted = true
        #expect(!snapshot.caregivers.contains { $0.id == person.id })
        #expect(snapshot.caregiverName(person.id) == "Alex")
        #expect(snapshot.pumps == [pump])
        #expect(snapshot.pumpingHistoryCaregivers.contains { $0.id == person.id })
        #expect(snapshot.recentCare(for: child.id).contains(.pumping(pump)))
        #expect(CareSearchCatalog.documents(in: snapshot).first?.subjectName == "Alex")
        #expect(
            LogAnalytics.pumpingDays(
                sessions: snapshot.pumps, familyID: child.familyID, motherID: person.id,
                count: 1, now: fixture.now, timeZone: .gmt
            ).first?.totalML == 105)
        #expect(throws: LogError.self) { try LogRules.mother(person.id, in: snapshot) }
        #expect(throws: LogError.self) {
            try LogRules.validate(.pumping(pump), in: snapshot, now: fixture.now)
        }
    }

    @Test func restorationCannotReintroduceDuplicateAccountOrInvitation() throws {
        let invitation = CaregiverInvitation(
            shareRecordName: "share", participantID: "member", accountIdentity: "account")
        var (snapshot, person) = state(invitation: invitation)
        let other = Caregiver(familyID: fixture.familyID, name: "Alex linked", cloudIdentity: "account")
        append(.caregiver(other), to: &snapshot)
        #expect(throws: LogError.self) {
            try CaregiverDeletionRules.validateRestoration(
                person, in: snapshot, actorID: fixture.personID, canEdit: true)
        }
        var unreserved = person
        unreserved.invitation = nil
        try CaregiverDeletionRules.validateRestoration(
            unreserved, in: snapshot, actorID: fixture.personID, canEdit: true)
        #expect(throws: LogError.self) {
            try CaregiverDeletionRules.validateRestoration(
                unreserved, in: snapshot, actorID: person.id, canEdit: true)
        }
    }

    @Test func missingForeignAndConflictedProfilesCannotBeDeleted() throws {
        var (snapshot, person) = state()
        #expect(throws: LogError.self) {
            try CaregiverDeletionRules.validate(
                UUID(), in: snapshot, actorID: fixture.personID, canEdit: true)
        }
        let foreign = Caregiver(familyID: UUID(), name: "Other family")
        append(.caregiver(foreign), to: &snapshot)
        #expect(throws: LogError.self) {
            try CaregiverDeletionRules.validate(
                foreign.id, in: snapshot, actorID: fixture.personID, canEdit: true)
        }
        let index = try #require(snapshot.records.firstIndex { $0.id == person.id })
        var branch = snapshot.records[index].revision
        branch.id = UUID()
        snapshot.records[index].heads.append(branch)
        #expect(throws: LogError.self) {
            try CaregiverDeletionRules.validate(
                person.id, in: snapshot, actorID: fixture.personID, canEdit: true)
        }
    }
}
