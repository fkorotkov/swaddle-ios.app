import Foundation

enum CaregiverDeletionRules {
    /// Deleting a profile is a recoverable revision, never a CloudKit access change.
    static func validate(
        _ id: UUID, in snapshot: FamilySnapshot, actorID: UUID,
        canEdit: Bool, resolvingDeletion: Bool = false
    ) throws -> Caregiver {
        guard canEdit, let family = snapshot.family, family.ownerID == actorID else {
            throw LogError.message(String(localized: "Only the family owner can delete a caregiver profile."))
        }
        guard id != family.ownerID, id != actorID else {
            throw LogError.message(String(localized: "Your own profile and the family owner’s profile can’t be deleted."))
        }
        guard let record = snapshot.record(id), case .caregiver(let person) = record.revision.value,
            person.familyID == family.id
        else {
            throw LogError.message(String(localized: "This caregiver profile is no longer available."))
        }
        // Inspect every current branch so a concurrent account link cannot be
        // discarded by deleting an older, unlinked version of the same profile.
        guard
            !record.heads.contains(where: {
                if case .caregiver(let head) = $0.value { return head.cloudIdentity != nil }
                return false
            })
        else {
            throw LogError.message(
                String(localized: "This profile is linked to an Apple Account. Keep it for their sign-in, and use Family sharing to manage their access.")
            )
        }
        guard !record.hasConflict || resolvingDeletion else {
            throw LogError.message(String(localized: "Review this caregiver’s competing edits before deleting the profile."))
        }
        guard
            !snapshot.activities.contains(where: {
                if case .nursing(let session) = $0.payload {
                    return session.caregiverID == id && !session.finished
                }
                return false
            })
        else {
            throw LogError.message(
                String(localized: "Finish this caregiver’s breastfeeding session before deleting the profile."))
        }
        return person
    }

    static func validateRestoration(
        _ person: Caregiver, in snapshot: FamilySnapshot,
        actorID: UUID, canEdit: Bool
    ) throws {
        guard canEdit, let family = snapshot.family, family.ownerID == actorID,
            person.familyID == family.id
        else {
            throw LogError.message(String(localized: "Only the family owner can restore a caregiver profile."))
        }
        let identities = Set(
            [person.cloudIdentity, person.invitation?.accountIdentity].compactMap { $0 })
        for other in snapshot.caregivers where other.id != person.id {
            let otherIdentities = Set(
                [other.cloudIdentity, other.invitation?.accountIdentity].compactMap { $0 })
            let sameInvitation =
                person.invitation.map { invitation in
                    other.invitation?.shareRecordName == invitation.shareRecordName
                        && other.invitation?.participantID == invitation.participantID
                } ?? false
            guard identities.isDisjoint(with: otherIdentities), !sameInvitation else {
                throw LogError.message(
                    String(localized: "This Apple Account or invitation now belongs to another caregiver. Restore a version without that invitation to keep their sign-in working.")
                )
            }
        }
    }
}
