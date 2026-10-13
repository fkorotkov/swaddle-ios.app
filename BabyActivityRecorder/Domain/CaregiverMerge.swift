import Foundation

struct CaregiverMergePlan: Equatable {
    var source: Caregiver
    var destination: Caregiver
    var sourceHeads: Set<UUID>
    var destinationHeads: Set<UUID>
    var pumpingCount: Int
}

enum CaregiverMergeRules {
    static func plan(
        sourceID: UUID, destinationID: UUID, in snapshot: FamilySnapshot,
        actorID: UUID, canEdit: Bool
    ) throws -> CaregiverMergePlan {
        guard sourceID != destinationID else {
            throw LogError.message(String(localized: "Choose two different caregiver profiles."))
        }
        let source = try CaregiverDeletionRules.validate(
            sourceID, in: snapshot, actorID: actorID, canEdit: canEdit)
        guard let from = snapshot.record(sourceID), !from.isDeleted,
            let to = snapshot.record(destinationID), !to.isDeleted,
            case .caregiver(var destination) = to.revision.value,
            destination.familyID == source.familyID,
            source.mergedIntoID == nil, destination.mergedIntoID == nil
        else { throw LogError.message(String(localized: "Choose two active profiles in this family.")) }
        guard !to.hasConflict else {
            throw LogError.message(String(localized: "Review the other caregiver’s competing edits before merging."))
        }
        if let invitation = source.invitation {
            let sameAccount =
                invitation.accountIdentity.map {
                    $0 == destination.cloudIdentity || $0 == destination.invitation?.accountIdentity
                } ?? false
            let sameParticipant =
                destination.invitation.map {
                    $0.shareRecordName == invitation.shareRecordName
                        && $0.participantID == invitation.participantID
                } ?? false
            guard sameAccount || sameParticipant else {
                throw LogError.message(
                    String(localized: "Keep the profile with the invitation. If these invitations are for different people, manage them in Family sharing first.")
                )
            }
        }
        guard
            !snapshot.activities.contains(where: {
                if case .nursing(let session) = $0.payload {
                    return !session.finished && session.caregiverID == destinationID
                }
                return false
            })
        else {
            throw LogError.message(
                String(localized: "Finish the breastfeeding session before merging these profiles."))
        }
        // Keeping either profile must preserve the ability to record pumping.
        destination.isMother =
            destination.isMother || source.isMother
            || snapshot.pumps.contains { $0.motherID == sourceID || $0.motherID == destinationID }
        // Preserve an explicit choice; never infer sex from pumping capability.
        destination.sex = destination.sex ?? source.sex
        return CaregiverMergePlan(
            source: source, destination: destination,
            sourceHeads: Set(from.heads.map(\.id)), destinationHeads: Set(to.heads.map(\.id)),
            pumpingCount: snapshot.pumps.filter {
                $0.motherID == sourceID || $0.motherID == destinationID
            }.count)
    }

    /// A late edit to a pre-merge entry retains its original ownership so separating
    /// profiles remains reversible. New entries use the kept profile instead.
    static func preparing(
        _ value: RecordValue, previous: RecordValue?, in snapshot: FamilySnapshot
    ) -> RecordValue {
        switch value {
        case .pumping(var pump):
            let target = snapshot.canonicalCaregiverID(pump.motherID)
            if case .pumping(let old) = previous,
                snapshot.canonicalCaregiverID(old.motherID) == target
            {
                pump.motherID = old.motherID
            } else {
                pump.motherID = target
            }
            return .pumping(pump)
        case .activity(var activity):
            guard case .nursing(var nursing) = activity.payload else { return value }
            let target = snapshot.canonicalCaregiverID(nursing.caregiverID)
            if case .activity(let old) = previous, case .nursing(let prior) = old.payload,
                snapshot.canonicalCaregiverID(prior.caregiverID) == target
            {
                nursing.caregiverID = prior.caregiverID
            } else {
                nursing.caregiverID = target
            }
            activity.payload = .nursing(nursing)
            return .activity(activity)
        default: return value
        }
    }
}
