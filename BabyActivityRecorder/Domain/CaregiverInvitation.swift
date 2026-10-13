import Foundation

/// A profile reservation for a participant returned by CloudKit. Names and email
/// addresses are never used to claim a profile. Optional on older caregiver data.
struct CaregiverInvitation: Codable, Equatable, Sendable {
    var shareRecordName: String
    var participantID: String
    var accountIdentity: String?
}

/// Constructed only from the signed-in, accepted participant in a CKShare.
nonisolated struct AcceptedCaregiverIdentity: Equatable, Sendable {
    var shareRecordName: String
    var participantID: String
    var accountIdentity: String
    /// The accepted participant's record identity, verified by CloudKit as the
    /// signed-in person. It may differ from CKContainer.userRecordID().
    var participantAccountIdentity: String? = nil
    /// Only a server-verified current participant can resolve this placeholder.
    var usesCurrentUserAlias = false
}

enum CaregiverInvitationRules {
    static func email(_ text: String) throws -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              !parts[1].hasPrefix("."), !parts[1].hasSuffix("."),
              !value.contains(where: { $0.isWhitespace || $0.isNewline }),
              !value.contains(where: { "<>,;".contains($0) }) else {
            throw LogError.message(String(localized: "Enter the email address they use with their Apple Account."))
        }
        return value
    }

    static func reserving(_ id: UUID, for invitation: CaregiverInvitation, in snapshot: FamilySnapshot,
                          actorID: UUID, replacingRemovedInvitation: Bool = false) throws -> Caregiver {
        guard let family = snapshot.family, family.ownerID == actorID else {
            throw LogError.message(String(localized: "Only the family owner can invite someone to a caregiver profile."))
        }
        guard id != family.ownerID, var person = snapshot.caregivers.first(where: { $0.id == id }),
              person.familyID == family.id else {
            throw LogError.message(String(localized: "Choose another caregiver’s profile to invite them."))
        }
        guard snapshot.record(id)?.hasConflict != true else {
            throw LogError.message(String(localized: "Resolve this caregiver’s conflicting edits before inviting them."))
        }
        guard !invitation.shareRecordName.isEmpty, !invitation.participantID.isEmpty else {
            throw LogError.message(String(localized: "iCloud couldn’t identify this invitation. Please try again."))
        }
        let sameReservedParticipant = person.invitation.map {
            $0.shareRecordName == invitation.shareRecordName && $0.participantID == invitation.participantID
                && $0.accountIdentity == invitation.accountIdentity
        } ?? false
        if let account = person.cloudIdentity, account != invitation.accountIdentity, !sameReservedParticipant {
            throw LogError.message(String(localized: "This profile is already linked to another Apple Account. Manage its access in Family sharing."))
        }
        if let prior = person.invitation, prior != invitation,
           !(prior.shareRecordName == invitation.shareRecordName && prior.participantID == invitation.participantID),
           !replacingRemovedInvitation {
            throw LogError.message(String(localized: "This profile already has an invitation for someone else. Remove that invitation in Family sharing first."))
        }
        for other in snapshot.caregivers where other.id != id {
            let sameAccount = invitation.accountIdentity.map {
                other.cloudIdentity == $0 || other.invitation?.accountIdentity == $0
            } ?? false
            let sameParticipant = other.invitation.map {
                $0.shareRecordName == invitation.shareRecordName && $0.participantID == invitation.participantID
            } ?? false
            if sameAccount || sameParticipant {
                throw LogError.message(String(localized: "This Apple Account already belongs to \(other.name)’s profile. Use that profile instead."))
            }
        }
        person.invitation = invitation
        return person
    }

    static func profile(for account: String, participant: AcceptedCaregiverIdentity?,
                        in snapshot: FamilySnapshot) throws -> Caregiver? {
        if let participant, participant.accountIdentity != account {
            throw LogError.message(String(localized: "The invitation belongs to a different Apple Account."))
        }
        let matches = snapshot.caregivers.filter { person in
            if person.cloudIdentity == account { return true }
            guard let participant, let invitation = person.invitation,
                  person.id != snapshot.family?.ownerID,
                  invitation.shareRecordName == participant.shareRecordName else { return false }
            return invitation.participantID == participant.participantID || invitation.accountIdentity == account
        }
        guard matches.count <= 1 else {
            throw LogError.message(String(localized: "More than one caregiver profile is linked to your invitation. Ask the family owner to resolve the profiles; your history is preserved."))
        }
        guard let person = matches.first else { return nil }
        guard snapshot.record(person.id)?.hasConflict != true else {
            throw LogError.message(String(localized: "Resolve this caregiver’s conflicting edits before linking the Apple Account."))
        }
        if let linked = person.cloudIdentity, linked != account {
            throw LogError.message(String(localized: "This caregiver profile is already linked to a different Apple Account."))
        }
        if person.cloudIdentity != account, let invitation = person.invitation,
           let reserved = invitation.accountIdentity, reserved != account {
            // A record-name mismatch alone isn't a different person. Only the
            // same accepted participant in this share can verify this alias.
            guard let participant, invitation.shareRecordName == participant.shareRecordName,
                  invitation.participantID == participant.participantID,
                  participant.participantAccountIdentity == reserved || participant.usesCurrentUserAlias else {
                throw LogError.message(String(localized: "This invitation is reserved for a different Apple Account."))
            }
        }
        return person
    }
}
