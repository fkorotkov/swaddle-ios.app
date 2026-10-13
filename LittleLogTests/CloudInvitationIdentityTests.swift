import CloudKit
import Foundation
import Testing
@testable import BabyActivityRecorder

struct CloudInvitationIdentityTests {
    private let account = "recipient-account"
    private let familyID = UUID()
    private let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare,
                                     zoneID: CKRecordZone.ID(zoneName: "family-zone", ownerName: "owner"))

    private func snapshot(role: CKShare.ParticipantRole = .privateUser,
                          status: CKShare.ParticipantAcceptanceStatus = .accepted,
                          permission: CKShare.ParticipantPermission = .readWrite) -> CloudInvitationSnapshot {
        let person = CloudInvitationSnapshot.Participant(id: "recipient", accountIdentity: account,
            membership: .init(status: status, role: role, permission: permission))
        return CloudInvitationSnapshot(recordID: shareID, currentParticipant: person, participants: [person])
    }

    @Test func reopeningAcceptedInvitationRefreshesIdentityAndPendingInvitationResumesAcceptance() throws {
        #expect(try CloudInvitationAction.resolve(hasFamily: true, existingShareID: shareID, incomingShareID: shareID,
                                                  status: .accepted) == .refreshIdentity)
        #expect(try CloudInvitationAction.resolve(hasFamily: true, existingShareID: shareID, incomingShareID: shareID,
                                                  status: .pending) == .acceptAndImport)
        // An account may have accepted elsewhere, but this phone still needs
        // Core Data to attach the shared store and import its family.
        #expect(try CloudInvitationAction.resolve(hasFamily: false, existingShareID: nil, incomingShareID: shareID,
                                                  status: .accepted) == .acceptAndImport)
        let other = CKRecord.ID(recordName: CKRecordNameZoneWideShare,
                                zoneID: CKRecordZone.ID(zoneName: "another-family", ownerName: "owner"))
        #expect(throws: LogError.self) {
            try CloudInvitationAction.resolve(hasFamily: true, existingShareID: shareID, incomingShareID: other, status: .accepted)
        }
        #expect(throws: LogError.self) {
            try CloudInvitationAction.resolve(hasFamily: true, existingShareID: nil, incomingShareID: shareID, status: .accepted)
        }
    }

    @Test(arguments: [CKShare.ParticipantRole.privateUser, .administrator])
    func acceptedPrivateMembersIncludingAdministratorsCanJoin(role: CKShare.ParticipantRole) throws {
        let accepted = try snapshot(role: role).acceptedIdentity(account: account)
        #expect(accepted.participantID == "recipient")
        #expect(accepted.accountIdentity == account)
    }

    @Test func metadataAcceptanceRecoversAStalePendingParticipant() throws {
        var value = snapshot(status: .pending)
        #expect(throws: CloudInvitationError.pending) { try value.acceptedIdentity(account: account) }
        value.metadataMembership = .init(status: .accepted, role: .administrator, permission: .readWrite)
        #expect(try value.acceptedIdentity(account: account).participantID == "recipient")
    }

    @Test func newerRemovalOverridesACachedAcceptedParticipant() {
        var value = snapshot()
        value.metadataMembership = .init(status: .removed, role: .privateUser, permission: .none)
        #expect(throws: CloudInvitationError.removed) { try value.acceptedIdentity(account: account) }
    }

    @Test func missingCurrentParticipantUsesOnlyAUniqueVerifiedAccountMatch() throws {
        var value = snapshot()
        value.currentParticipant = nil
        #expect(try value.acceptedIdentity(account: account).participantID == "recipient")
        #expect(throws: CloudInvitationError.participantUnavailable) { try value.acceptedIdentity(account: "someone-else") }
        value.participants.append(value.participants[0])
        #expect(throws: CloudInvitationError.participantUnavailable) { try value.acceptedIdentity(account: account) }
    }

    @Test func currentParticipantWithoutDisclosedRecordIDStillIdentifiesCurrentUser() throws {
        var value = snapshot()
        value.currentParticipant?.accountIdentity = nil
        #expect(try value.acceptedIdentity(account: account).accountIdentity == account)
        value.currentParticipant = nil
        value.participants[0].accountIdentity = nil
        #expect(throws: CloudInvitationError.participantUnavailable) { try value.acceptedIdentity(account: account) }
    }

    @Test func neverSwitchesToAnotherParticipantWhenCurrentAccountConflicts() {
        var value = snapshot()
        value.currentParticipant?.accountIdentity = "different-account"
        #expect(throws: CloudInvitationError.accountMismatch) { try value.acceptedIdentity(account: account) }
    }

    @Test func cloudKitVerifiedIdentityCanUseADifferentRecordName() throws {
        var value = snapshot()
        value.currentParticipant?.accountIdentity = "share-specific-identity"
        #expect(throws: CloudInvitationError.accountMismatch) { try value.acceptedIdentity(account: account) }
        value.currentParticipant?.verifiedAccountIdentity = account
        let accepted = try value.acceptedIdentity(account: account)
        #expect(accepted.accountIdentity == account)
        #expect(accepted.participantAccountIdentity == "share-specific-identity")
        #expect(accepted.participantID == "recipient")
        // Verification is scoped to the exact account, not a generic bypass.
        #expect(throws: CloudInvitationError.accountMismatch) { try value.acceptedIdentity(account: "another-account") }
    }

    @Test func verifiedPersonStillNeedsAcceptedPrivateAccess() {
        var value = snapshot(status: .pending)
        value.currentParticipant?.accountIdentity = "share-specific-identity"
        value.currentParticipant?.verifiedAccountIdentity = account
        #expect(throws: CloudInvitationError.pending) { try value.acceptedIdentity(account: account) }
        value.metadataMembership = .init(status: .removed, role: .administrator, permission: .readWrite)
        #expect(throws: CloudInvitationError.removed) { try value.acceptedIdentity(account: account) }
        value.metadataMembership = .init(status: .accepted, role: .publicUser, permission: .readWrite)
        #expect(throws: CloudInvitationError.unsupportedAccess) { try value.acceptedIdentity(account: account) }
    }

    @Test func acceptedCurrentUserAliasDoesNotNeedASecondPersonLookup() throws {
        // Reproduce the reported 2/3/3 membership with no matching account
        // record in the roster. CloudKit still identifies currentUserParticipant.
        let membership = CloudInvitationSnapshot.Membership(status: .init(rawValue: 2)!, role: .init(rawValue: 3)!,
                                                           permission: .init(rawValue: 3)!)
        let alias = CloudInvitationSnapshot.Participant(id: "reserved-participant", accountIdentity: nil,
                                                        membership: membership, usesCurrentUserAlias: true)
        let value = CloudInvitationSnapshot(recordID: shareID, publicPermission: .init(rawValue: 1)!,
                                           currentParticipant: alias, participants: [alias], metadataMembership: membership)
        #expect(throws: CloudInvitationError.accountMismatch) { try value.acceptedIdentity(account: account) }
        let verified = try value.verifyingCurrentParticipant(account: account)
        let accepted = try verified.acceptedIdentity(account: account)
        #expect(accepted.participantID == "reserved-participant")
        #expect(accepted.accountIdentity == account)
        #expect(accepted.participantAccountIdentity == nil)
        #expect(accepted.usesCurrentUserAlias)
        #expect(throws: CloudInvitationError.accountMismatch) { try verified.acceptedIdentity(account: "other-account") }
    }

    @Test func aRosterAliasCannotStandInForTheServersCurrentParticipant() throws {
        var value = snapshot()
        value.currentParticipant = nil
        value.participants[0].accountIdentity = nil
        value.participants[0].usesCurrentUserAlias = true
        #expect(throws: CloudInvitationError.participantUnavailable) {
            try value.verifyingCurrentParticipant(account: account)
        }
        value.participants = [snapshot().participants[0]]
        #expect(try value.verifyingCurrentParticipant(account: account).acceptedIdentity(account: account).participantID == "recipient")
        value.participants.append(value.participants[0])
        #expect(throws: CloudInvitationError.participantUnavailable) {
            try value.verifyingCurrentParticipant(account: account)
        }
    }

    @Test func authenticatedAliasStillRequiresAcceptedPrivateAccess() throws {
        var value = snapshot(status: .pending)
        value.currentParticipant?.accountIdentity = nil
        value.currentParticipant?.usesCurrentUserAlias = true
        value = try value.verifyingCurrentParticipant(account: account)
        #expect(throws: CloudInvitationError.pending) { try value.acceptedIdentity(account: account) }
        value.metadataMembership = .init(status: .removed, role: .privateUser, permission: .none)
        #expect(throws: CloudInvitationError.removed) { try value.acceptedIdentity(account: account) }
        value.metadataMembership = .init(status: .accepted, role: .publicUser, permission: .readWrite)
        #expect(throws: CloudInvitationError.unsupportedAccess) { try value.acceptedIdentity(account: account) }
        value.metadataMembership = .init(status: .accepted, role: .privateUser, permission: .readOnly)
        #expect(try value.acceptedIdentity(account: account).usesCurrentUserAlias)
        value.publicPermission = .readOnly
        #expect(throws: CloudInvitationError.unsupportedAccess) { try value.acceptedIdentity(account: account) }
    }

    @Test func troubleshootingTextDoesNotExposeIdentifiersOrSharedContent() {
        let share = CKShare(recordZoneID: CKRecordZone.ID(zoneName: "private-family-zone"))
        share[CKShare.SystemFieldKey.title] = "Private family name" as NSString
        let person = CKShare.Participant.oneTimeURLParticipant()
        let report = CloudInvitationSnapshot.diagnostics(share: share, metadata: nil, account: account)
        for privateValue in [account, person.participantID, share.recordID.zoneID.zoneName, "Private family name"] {
            #expect(!report.contains(privateValue))
        }
    }

    @Test(arguments: [CKShare.ParticipantRole.owner, .unknown, .publicUser])
    func anUnacceptedOrPublicRoleCannotClaimACaregiver(role: CKShare.ParticipantRole) {
        #expect(throws: CloudInvitationError.unsupportedAccess) { try snapshot(role: role).acceptedIdentity(account: account) }
    }

    @Test func removedPendingUnknownAndPermissionlessParticipantsStayBlocked() {
        #expect(throws: CloudInvitationError.pending) { try snapshot(status: .pending).acceptedIdentity(account: account) }
        #expect(throws: CloudInvitationError.removed) { try snapshot(status: .removed).acceptedIdentity(account: account) }
        #expect(throws: CloudInvitationError.participantUnavailable) { try snapshot(status: .unknown).acceptedIdentity(account: account) }
        #expect(throws: CloudInvitationError.unsupportedAccess) { try snapshot(permission: .none).acceptedIdentity(account: account) }
        #expect(throws: CloudInvitationError.unsupportedAccess) { try snapshot(permission: .unknown).acceptedIdentity(account: account) }
    }

    @Test func readOnlyMembershipIsRecognizedWithoutChangingItsPermission() throws {
        let value = snapshot(permission: .readOnly)
        #expect(try value.acceptedIdentity(account: account).participantID == "recipient")
        #expect(value.currentParticipant?.membership.permission == .readOnly)
    }

    @Test func aPublicShareCannotClaimAPrivateProfile() {
        var value = snapshot()
        value.publicPermission = .readWrite
        #expect(throws: CloudInvitationError.unsupportedAccess) { try value.acceptedIdentity(account: account) }
    }

    @Test func verifiedIdentityIsScopedToFamilyAccountAndFullZoneID() throws {
        let participant = try snapshot().acceptedIdentity(account: account)
        let cache = VerifiedCaregiverInvitation(familyID: familyID, shareRecordID: shareID, participant: participant)
        #expect(cache.identity(familyID: familyID, shareRecordID: shareID, account: account) == participant)
        #expect(cache.identity(familyID: UUID(), shareRecordID: shareID, account: account) == nil)
        #expect(cache.identity(familyID: familyID, shareRecordID: shareID, account: "other") == nil)
        let anotherZone = CKRecord.ID(recordName: CKRecordNameZoneWideShare,
                                     zoneID: CKRecordZone.ID(zoneName: "another-zone", ownerName: "owner"))
        let anotherOwner = CKRecord.ID(recordName: CKRecordNameZoneWideShare,
                                      zoneID: CKRecordZone.ID(zoneName: "family-zone", ownerName: "someone-else"))
        #expect(cache.identity(familyID: familyID, shareRecordID: anotherZone, account: account) == nil)
        #expect(cache.identity(familyID: familyID, shareRecordID: anotherOwner, account: account) == nil)
    }
}
