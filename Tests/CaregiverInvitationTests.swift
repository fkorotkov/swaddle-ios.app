import Foundation
import Testing
@testable import LittleLogCore

struct CaregiverInvitationTests {
    private let familyID = UUID()
    private let ownerID = UUID()
    private let recipientID = UUID()
    private var link: CaregiverInvitation {
        .init(shareRecordName: "private-share", participantID: "cloudkit-participant", accountIdentity: "recipient-account")
    }
    private var accepted: AcceptedCaregiverIdentity {
        .init(shareRecordName: link.shareRecordName, participantID: link.participantID, accountIdentity: "recipient-account")
    }
    private func snapshot(invitation: CaregiverInvitation? = nil, linked: String? = nil, extra: [Caregiver] = []) -> FamilySnapshot {
        let people = [Caregiver(id: ownerID, familyID: familyID, name: "Sam", cloudIdentity: "owner-account"),
                      Caregiver(id: recipientID, familyID: familyID, name: "Alex", isMother: true, cloudIdentity: linked, invitation: invitation)] + extra
        let revisions = people.map { person in
            RecordRevision(id: UUID(), recordID: person.id, parentIDs: [], value: .caregiver(person), date: .now, editorID: ownerID, deleted: false)
        }
        return FamilySnapshot(family: Family(id: familyID, name: "Family", timeZoneIdentifier: "America/New_York", ownerID: ownerID),
                              records: RevisionProjection.project(revisions))
    }

    @Test func oldProfilesDecodeWithoutAnInvitation() throws {
        let old = """
        {"id":"\(recipientID)","familyID":"\(familyID)","name":"Alex","isMother":true}
        """
        let person = try JSONDecoder().decode(Caregiver.self, from: Data(old.utf8))
        #expect(person.invitation == nil)
        #expect(person.isMother)
        var linked = person
        linked.invitation = link
        #expect(try JSONDecoder().decode(Caregiver.self, from: JSONEncoder().encode(linked)) == linked)
    }

    @Test func onlyOwnerCanReserveAnotherCaregiversProfile() throws {
        let result = try CaregiverInvitationRules.reserving(recipientID, for: link, in: snapshot(), actorID: ownerID)
        #expect(result.id == recipientID && result.isMother && result.cloudIdentity == nil)
        #expect(result.invitation == link)
        #expect(throws: LogError.self) { try CaregiverInvitationRules.reserving(recipientID, for: link, in: snapshot(), actorID: UUID()) }
        #expect(throws: LogError.self) { try CaregiverInvitationRules.reserving(ownerID, for: link, in: snapshot(), actorID: ownerID) }
    }

    @Test func retryKeepsTheSameReservationAndDifferentRecipientNeedsRevocation() throws {
        let state = snapshot(invitation: link)
        #expect(try CaregiverInvitationRules.reserving(recipientID, for: link, in: state, actorID: ownerID).invitation == link)
        let other = CaregiverInvitation(shareRecordName: link.shareRecordName, participantID: "other", accountIdentity: "other-account")
        #expect(throws: LogError.self) { try CaregiverInvitationRules.reserving(recipientID, for: other, in: state, actorID: ownerID) }
        #expect(try CaregiverInvitationRules.reserving(recipientID, for: other, in: state, actorID: ownerID, replacingRemovedInvitation: true).invitation == other)
        #expect(throws: LogError.self) {
            try CaregiverInvitationRules.reserving(recipientID, for: other, in: snapshot(invitation: link, linked: "recipient-account"), actorID: ownerID, replacingRemovedInvitation: true)
        }
    }

    @Test func duplicateAccountAndPendingParticipantCannotUseTwoProfiles() {
        let other = Caregiver(familyID: familyID, name: "Other", cloudIdentity: "recipient-account")
        #expect(throws: LogError.self) { try CaregiverInvitationRules.reserving(recipientID, for: link, in: snapshot(extra: [other]), actorID: ownerID) }
        let unknown = CaregiverInvitation(shareRecordName: link.shareRecordName, participantID: link.participantID, accountIdentity: nil)
        let pending = Caregiver(familyID: familyID, name: "Other", invitation: unknown)
        #expect(throws: LogError.self) { try CaregiverInvitationRules.reserving(recipientID, for: unknown, in: snapshot(extra: [pending]), actorID: ownerID) }
    }

    @Test func unknownAccountMatchesOnlyTheAcceptedCloudKitParticipant() throws {
        var pending = link
        pending.accountIdentity = nil
        let state = snapshot(invitation: pending)
        #expect(try CaregiverInvitationRules.profile(for: "recipient-account", participant: accepted, in: state)?.id == recipientID)
        #expect(try CaregiverInvitationRules.profile(for: "recipient-account", participant: nil, in: state) == nil)
        var wrongShare = accepted
        wrongShare.shareRecordName = "another-share"
        #expect(try CaregiverInvitationRules.profile(for: "recipient-account", participant: wrongShare, in: state) == nil)
        var wrongPerson = accepted
        wrongPerson.participantID = "someone-else"
        #expect(try CaregiverInvitationRules.profile(for: "recipient-account", participant: wrongPerson, in: state) == nil)
        #expect(throws: LogError.self) { try CaregiverInvitationRules.profile(for: "another-account", participant: accepted, in: state) }
    }

    @Test func verifiedAccountSupportsAliasesWithoutMatchingNames() throws {
        var alias = accepted
        alias.participantID = "another-lookup-for-same-account"
        #expect(try CaregiverInvitationRules.profile(for: "recipient-account", participant: alias, in: snapshot(invitation: link))?.id == recipientID)
        let sameName = Caregiver(familyID: familyID, name: "Alex")
        #expect(try CaregiverInvitationRules.profile(for: "recipient-account", participant: accepted, in: snapshot(extra: [sameName])) == nil)
    }

    @Test func conflictingOrAlreadyLinkedProfilesDoNotSilentlySwitchPeople() {
        #expect(throws: LogError.self) { try CaregiverInvitationRules.profile(for: "recipient-account", participant: accepted, in: snapshot(invitation: link, linked: "someone-else")) }
        let duplicate = Caregiver(familyID: familyID, name: "Other", cloudIdentity: "recipient-account")
        #expect(throws: LogError.self) { try CaregiverInvitationRules.profile(for: "recipient-account", participant: accepted, in: snapshot(invitation: link, extra: [duplicate])) }
    }

    @Test func cloudKitVerifiedAliasClaimsOnlyTheSameReservedParticipant() throws {
        var verified = accepted
        verified.accountIdentity = "canonical-account"
        verified.participantAccountIdentity = link.accountIdentity
        #expect(try CaregiverInvitationRules.profile(for: "canonical-account", participant: verified,
                                                      in: snapshot(invitation: link))?.id == recipientID)
        verified.participantAccountIdentity = "unrelated-record"
        #expect(throws: LogError.self) {
            try CaregiverInvitationRules.profile(for: "canonical-account", participant: verified, in: snapshot(invitation: link))
        }
        verified.participantAccountIdentity = link.accountIdentity
        verified.participantID = "someone-else"
        #expect(try CaregiverInvitationRules.profile(for: "canonical-account", participant: verified,
                                                      in: snapshot(invitation: link)) == nil)
    }

    @Test func verifiedAliasSurvivesRelaunchAndResendingWithoutReassigningTheProfile() throws {
        let state = snapshot(invitation: link, linked: "canonical-account")
        #expect(try CaregiverInvitationRules.profile(for: "canonical-account", participant: nil, in: state)?.id == recipientID)
        #expect(try CaregiverInvitationRules.reserving(recipientID, for: link, in: state, actorID: ownerID).invitation == link)
        var other = link
        other.accountIdentity = "someone-else"
        #expect(throws: LogError.self) {
            try CaregiverInvitationRules.reserving(recipientID, for: other, in: state, actorID: ownerID)
        }
        other = link
        other.participantID = "someone-else"
        #expect(throws: LogError.self) {
            try CaregiverInvitationRules.reserving(recipientID, for: other, in: state, actorID: ownerID, replacingRemovedInvitation: true)
        }
    }

    @Test func currentUserAliasClaimsOnlyItsReservedParticipantAndKeepsLinkedAccountsProtected() throws {
        var alias = accepted
        alias.accountIdentity = "canonical-account"
        alias.usesCurrentUserAlias = true
        #expect(try CaregiverInvitationRules.profile(for: "canonical-account", participant: alias,
                                                      in: snapshot(invitation: link))?.id == recipientID)
        #expect(throws: LogError.self) {
            try CaregiverInvitationRules.profile(for: "canonical-account", participant: alias,
                                                  in: snapshot(invitation: link, linked: "another-account"))
        }
        alias.participantID = "another-participant"
        #expect(try CaregiverInvitationRules.profile(for: "canonical-account", participant: alias,
                                                      in: snapshot(invitation: link)) == nil)
        alias.participantID = link.participantID
        alias.shareRecordName = "another-share"
        #expect(try CaregiverInvitationRules.profile(for: "canonical-account", participant: alias,
                                                      in: snapshot(invitation: link)) == nil)
    }

    @Test func validatesSingleEmailAndPreservesAddress() throws {
        #expect(try CaregiverInvitationRules.email("  Alex+swaddle@example.com \n") == "Alex+swaddle@example.com")
        for invalid in ["", "alex", "@example.com", "alex@", "alex@example", "alex@ example.com", "alex@example.com,other@example.com"] {
            #expect(throws: LogError.self) { try CaregiverInvitationRules.email(invalid) }
        }
    }
}
