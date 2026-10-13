import CloudKit
import Foundation

nonisolated enum CloudInvitationAction {
    case acceptAndImport, refreshIdentity

    static func resolve(hasFamily: Bool, existingShareID: CKRecord.ID?, incomingShareID: CKRecord.ID,
                        status: CKShare.ParticipantAcceptanceStatus) throws -> Self {
        guard hasFamily else { return .acceptAndImport }
        guard existingShareID == incomingShareID else {
            throw LogError.message(String(localized: "You already belong to a different family. Swaddle supports one family at a time. Your existing records have been kept."))
        }
        return status == .accepted ? .refreshIdentity : .acceptAndImport
    }
}

nonisolated enum CloudInvitationError: LocalizedError, Equatable {
    case syncing, participantUnavailable, pending, removed, accountMismatch, unsupportedAccess

    var errorDescription: String? {
        switch self {
        case .syncing:
            String(localized: "Your family is still downloading from iCloud. Keep Swaddle open, then check again.")
        case .participantUnavailable:
            String(localized: "iCloud hasn’t returned your invitation details yet. Check again, or reopen the original invitation.")
        case .pending:
            String(localized: "Open your iCloud invitation and accept it to finish joining this family.")
        case .removed:
            String(localized: "This invitation is no longer active. Ask the family owner to invite you again.")
        case .accountMismatch:
            String(localized: "This invitation doesn’t match the Apple Account signed into iCloud on this iPhone. Reopen the invitation with the invited account.")
        case .unsupportedAccess:
            String(localized: "iCloud hasn’t granted access to this family. Ask the family owner to check your sharing permissions.")
        }
    }
}

/// A value copy keeps CloudKit's identity/permission decisions testable without
/// manufacturing participants or changing their read-only acceptance status.
nonisolated struct CloudInvitationSnapshot: Sendable {
    struct Membership: Sendable {
        var status: CKShare.ParticipantAcceptanceStatus
        var role: CKShare.ParticipantRole
        var permission: CKShare.ParticipantPermission
        var isFamilyParticipant: Bool {
            if role == .privateUser { return true }
            if #available(iOS 26.0, macOS 26.0, *) { return role == .administrator }
            return false
        }
    }
    struct Participant: Sendable {
        var id: String
        var accountIdentity: String?
        var membership: Membership
        var usesCurrentUserAlias = false
        // Set only from a freshly fetched, authenticated share. CloudKit's
        // currentUserParticipant is authoritative even when its record is an alias.
        var verifiedAccountIdentity: String?
    }

    var recordID: CKRecord.ID
    var publicPermission: CKShare.ParticipantPermission = .none
    var currentParticipant: Participant?
    var participants: [Participant] = []
    var metadataMembership: Membership?

    func acceptedIdentity(account: String) throws -> AcceptedCaregiverIdentity {
        // Core Data's cached share may omit currentUserParticipant. A unique
        // match to CKContainer.userRecordID is also authoritative; names and
        // emails are never an identity fallback.
        let matches = participants.filter { $0.accountIdentity == account }
        guard let participant = currentParticipant ?? (matches.count == 1 ? matches.first : nil),
              !participant.id.isEmpty else { throw CloudInvitationError.participantUnavailable }
        if participant.usesCurrentUserAlias, participant.verifiedAccountIdentity != account {
            throw CloudInvitationError.accountMismatch
        }
        if let knownAccount = participant.accountIdentity, knownAccount != account,
           participant.verifiedAccountIdentity != account {
            throw CloudInvitationError.accountMismatch
        }
        // Fresh metadata reports the signed-in user's acceptance independently
        // of a cached participant object that may still say pending.
        let membership = metadataMembership ?? participant.membership
        switch membership.status {
        case .accepted: break
        case .pending: throw CloudInvitationError.pending
        case .removed: throw CloudInvitationError.removed
        default: throw CloudInvitationError.participantUnavailable
        }
        guard publicPermission == .none,
              membership.isFamilyParticipant,
              membership.permission == .readWrite || membership.permission == .readOnly else {
            throw CloudInvitationError.unsupportedAccess
        }
        return AcceptedCaregiverIdentity(shareRecordName: recordID.recordName,
                                         participantID: participant.id, accountIdentity: account,
                                         participantAccountIdentity: participant.accountIdentity,
                                         usesCurrentUserAlias: participant.usesCurrentUserAlias)
    }

    /// Call only for a share fetched from the signed-in account's database,
    /// never for Core Data's cached copy. The caller checks the account and
    /// full family/share context before and after the network request.
    func verifyingCurrentParticipant(account: String) throws -> Self {
        var result = self
        let matches = participants.filter { !$0.usesCurrentUserAlias && $0.accountIdentity == account }
        guard var current = currentParticipant ?? (matches.count == 1 ? matches.first : nil),
              !current.id.isEmpty else { throw CloudInvitationError.participantUnavailable }
        current.verifiedAccountIdentity = account
        result.currentParticipant = current
        return result
    }
}

extension CloudInvitationSnapshot {
    /// Intentionally excludes names, emails, record IDs, share URLs and care data.
    static func diagnostics(share: CKShare, metadata: CKShare.Metadata?, account: String) -> String {
        let current = share.currentUserParticipant
        let record = current?.userIdentity.userRecordID
        let recordComparison = record.map {
            $0.recordName == CKCurrentUserDefaultName ? "current-user alias"
                : (CareCloudAccount.identity($0) == account ? "matches account" : "different representation")
        } ?? "unavailable"
        return """
        Current participant: \(current == nil ? "unavailable" : "present")
        Participant record: \(recordComparison)
        Identity source: authenticated iCloud share
        Matching account records: \(share.participants.filter { $0.userIdentity.userRecordID.map(CareCloudAccount.identity) == account }.count)
        Participant status/role/permission: \(current?.acceptanceStatus.rawValue ?? -1)/\(current?.role.rawValue ?? -1)/\(current?.permission.rawValue ?? -1)
        Invitation status/role/permission: \(metadata?.participantStatus.rawValue ?? -1)/\(metadata?.participantRole.rawValue ?? -1)/\(metadata?.participantPermission.rawValue ?? -1)
        Public permission: \(share.publicPermission.rawValue)
        """
    }

    init(share: CKShare, metadata: CKShare.Metadata? = nil) {
        recordID = share.recordID
        publicPermission = share.publicPermission
        currentParticipant = share.currentUserParticipant.map(Participant.init)
        participants = share.participants.map(Participant.init)
        if let metadata {
            metadataMembership = Membership(status: metadata.participantStatus, role: metadata.participantRole,
                                            permission: metadata.participantPermission)
        }
    }
}

extension CloudInvitationSnapshot.Participant {
    init(_ participant: CKShare.Participant) {
        id = participant.participantID
        let record = participant.userIdentity.userRecordID
        usesCurrentUserAlias = record?.recordName == CKCurrentUserDefaultName
        // The default name means "me" on every account. Never persist its hash
        // as though it were a person's unique CloudKit identity.
        accountIdentity = usesCurrentUserAlias ? nil : record.map(CareCloudAccount.identity)
        membership = .init(status: participant.acceptanceStatus, role: participant.role, permission: participant.permission)
    }
}

/// Zone-wide shares all have the same record name. Scope a verified result to
/// the full record ID (including zone/owner), family, and signed-in account.
nonisolated struct VerifiedCaregiverInvitation {
    var familyID: UUID
    var shareRecordID: CKRecord.ID
    var participant: AcceptedCaregiverIdentity

    func identity(familyID: UUID, shareRecordID: CKRecord.ID, account: String) -> AcceptedCaregiverIdentity? {
        guard self.familyID == familyID, self.shareRecordID == shareRecordID,
              participant.accountIdentity == account else { return nil }
        return participant
    }
}
