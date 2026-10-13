import Foundation
import Testing

@testable import LittleLogCore

struct CaregiverMergeTests {
    private let fixture = LogRulesTests()

    private func setup() -> (FamilySnapshot, Caregiver, Caregiver) {
        var (snapshot, _) = fixture.fixture()
        let duplicate = Caregiver(familyID: fixture.familyID, name: "Alex old", isMother: true)
        let kept = Caregiver(
            familyID: fixture.familyID, name: "Alex", cloudIdentity: "alex-account")
        put(.caregiver(duplicate), in: &snapshot)
        put(.caregiver(kept), in: &snapshot)
        return (snapshot, duplicate, kept)
    }

    private func put(_ value: RecordValue, in snapshot: inout FamilySnapshot, deleted: Bool = false)
    {
        let parents = Set(snapshot.record(value.id)?.heads.map(\.id) ?? [])
        let revision = RecordRevision(
            id: UUID(), recordID: value.id, parentIDs: parents,
            value: value, date: fixture.now, editorID: fixture.personID, deleted: deleted)
        snapshot.records.removeAll { $0.id == value.id }
        snapshot.records.append(ProjectedRecord(revision: revision, heads: [revision]))
    }

    private func plan(_ source: Caregiver, _ destination: Caregiver, in snapshot: FamilySnapshot)
        throws -> CaregiverMergePlan
    {
        try CaregiverMergeRules.plan(
            sourceID: source.id, destinationID: destination.id,
            in: snapshot, actorID: fixture.personID, canEdit: true)
    }

    private func merge(
        _ source: Caregiver, _ destination: Caregiver, in snapshot: inout FamilySnapshot
    ) throws {
        let reviewed = try plan(source, destination, in: snapshot)
        var alias = reviewed.source
        alias.mergedIntoID = destination.id
        put(.caregiver(reviewed.destination), in: &snapshot)
        put(.caregiver(alias), in: &snapshot, deleted: true)
    }

    private func pump(_ person: Caregiver, volume: Decimal = 105, offset: TimeInterval = -60)
        -> PumpSession
    {
        PumpSession(
            familyID: fixture.familyID, motherID: person.id,
            occurredAt: fixture.now.addingTimeInterval(offset), authorID: fixture.personID,
            totalML: volume, unit: .ml, note: "Original")
    }

    @Test func mergeKeepsAccountAndProtectsOwnerReadOnlyAndLinkedSources() throws {
        let (snapshot, duplicate, kept) = setup()
        let reviewed = try plan(duplicate, kept, in: snapshot)
        #expect(reviewed.destination.cloudIdentity == "alex-account")
        #expect(reviewed.destination.isMother)
        for actor in [duplicate.id, kept.id] {
            #expect(throws: LogError.self) {
                try CaregiverMergeRules.plan(
                    sourceID: duplicate.id, destinationID: kept.id,
                    in: snapshot, actorID: actor, canEdit: true)
            }
        }
        #expect(throws: LogError.self) {
            try CaregiverMergeRules.plan(
                sourceID: duplicate.id, destinationID: kept.id,
                in: snapshot, actorID: fixture.personID, canEdit: false)
        }
        #expect(throws: LogError.self) { try plan(kept, duplicate, in: snapshot) }
        #expect(throws: LogError.self) { try plan(duplicate, duplicate, in: snapshot) }
        let owner = try #require(snapshot.caregivers.first { $0.id == fixture.personID })
        #expect(throws: LogError.self) { try plan(owner, kept, in: snapshot) }
        #expect(try plan(duplicate, owner, in: snapshot).destination.id == owner.id)
    }

    @Test func mergePreservesExplicitSexWithoutInferringItFromPumping() throws {
        var (snapshot, duplicate, kept) = setup()
        duplicate.sex = .female
        put(.caregiver(duplicate), in: &snapshot)
        #expect(try plan(duplicate, kept, in: snapshot).destination.sex == .female)
        kept.sex = .male
        put(.caregiver(kept), in: &snapshot)
        let explicit = try plan(duplicate, kept, in: snapshot).destination
        #expect(explicit.sex == .male && explicit.isMother)
    }

    @Test func invitationMayOnlyBeRemovedWhenKeptProfileRepresentsTheSameParticipant() throws {
        var (snapshot, duplicate, kept) = setup()
        duplicate.invitation = CaregiverInvitation(
            shareRecordName: "share", participantID: "alex", accountIdentity: "different")
        put(.caregiver(duplicate), in: &snapshot)
        #expect(throws: LogError.self) { try plan(duplicate, kept, in: snapshot) }
        duplicate.invitation?.accountIdentity = nil
        put(.caregiver(duplicate), in: &snapshot)
        #expect(throws: LogError.self) { try plan(duplicate, kept, in: snapshot) }
        duplicate.invitation?.accountIdentity = kept.cloudIdentity
        put(.caregiver(duplicate), in: &snapshot)
        #expect(
            try plan(duplicate, kept, in: snapshot).destination.cloudIdentity == kept.cloudIdentity)
        var invitedKeeper = kept
        invitedKeeper.cloudIdentity = nil
        invitedKeeper.invitation = duplicate.invitation
        put(.caregiver(invitedKeeper), in: &snapshot)
        #expect(try plan(duplicate, invitedKeeper, in: snapshot).source.id == duplicate.id)
    }

    @Test func combinedHistoryPreservesAmountsAuthorshipIDsIntakeSearchAndLatestPreset() throws {
        var (snapshot, duplicate, kept) = setup()
        let older = pump(kept, volume: 90, offset: -3600)
        let latest = pump(duplicate, volume: 105)
        put(.pumping(older), in: &snapshot)
        put(.pumping(latest), in: &snapshot)
        let child = try #require(snapshot.children.first)
        let bottle = Activity(
            familyID: fixture.familyID, childID: child.id, occurredAt: fixture.now,
            authorID: duplicate.id, payload: .bottle(Bottle(milkML: 60, formulaML: 30, unit: .ml)))
        put(.activity(bottle), in: &snapshot)
        let nursing = Activity(
            familyID: fixture.familyID, childID: child.id,
            occurredAt: fixture.now.addingTimeInterval(-600), authorID: duplicate.id,
            payload: .nursing(
                Nursing(
                    caregiverID: duplicate.id,
                    segments: [
                        NursingSegment(
                            side: .left, start: fixture.now.addingTimeInterval(-600),
                            end: fixture.now)
                    ], finished: true)))
        put(.activity(nursing), in: &snapshot)
        let originalPump = snapshot.record(latest.id)
        try merge(duplicate, kept, in: &snapshot)
        #expect(!snapshot.caregivers.contains { $0.id == duplicate.id })
        #expect(snapshot.record(latest.id) == originalPump)
        #expect(snapshot.pumps.count == 2)
        #expect(
            snapshot.pumps.allSatisfy { $0.motherID == kept.id && $0.authorID == fixture.personID })
        #expect(snapshot.pumps.reduce(Decimal(0)) { $0 + $1.totalML } == 195)
        #expect(
            snapshot.pumpingHistoryCaregivers.filter { $0.id == duplicate.id || $0.id == kept.id }
                .map(
                    \.id) == [kept.id])
        #expect(snapshot.caregiverName(duplicate.id) == "Alex old")
        #expect(snapshot.activities.first { $0.id == bottle.id } == bottle)
        #expect(
            ActivitySummary(activities: snapshot.activities, childID: child.id, end: fixture.now)
                .totalML
                == 90)
        #expect(
            PumpVolumePreset.latest(for: kept.id, in: snapshot, now: fixture.now)?.session.id
                == latest.id
        )
        #expect(
            CareSearchCatalog.documents(in: snapshot).filter { $0.caregiverID == kept.id }.count
                == 2)
        #expect(Set(snapshot.recentCare(for: child.id).map(\.id)).count == 4)
        if case .nursing(let result) = snapshot.activities.first(where: { $0.id == nursing.id })?
            .payload
        {
            #expect(result.caregiverID == kept.id)
        } else {
            Issue.record("Missing finished breastfeeding history")
        }
    }

    @Test func lateOfflineEntriesAndEditsRemainReversibleWithoutRewritingOriginalRecords() throws {
        var (snapshot, duplicate, kept) = setup()
        try merge(duplicate, kept, in: &snapshot)
        let late = pump(duplicate)
        put(.pumping(late), in: &snapshot)
        var edited = try #require(snapshot.pumps.first)
        edited.totalML = 120
        let prepared = CaregiverMergeRules.preparing(
            .pumping(edited), previous: .pumping(late), in: snapshot)
        put(prepared, in: &snapshot)
        #expect(snapshot.pumps.first?.motherID == kept.id)
        let newEntry = pump(duplicate, volume: 75)
        let newValue = CaregiverMergeRules.preparing(
            .pumping(newEntry), previous: nil, in: snapshot)
        put(newValue, in: &snapshot)
        put(.caregiver(duplicate), in: &snapshot)
        #expect(snapshot.pumps.first { $0.id == late.id }?.motherID == duplicate.id)
        #expect(snapshot.pumps.first { $0.id == late.id }?.totalML == 120)
        #expect(snapshot.pumps.first { $0.id == newEntry.id }?.motherID == kept.id)
        #expect(snapshot.pumps.count == 2)
    }

    @Test func chainedMergesMissingDestinationsCyclesAndOtherFamiliesNeverLoseHistory() throws {
        var (snapshot, first, kept) = setup()
        let middle = Caregiver(familyID: fixture.familyID, name: "Alex middle", isMother: true)
        put(.caregiver(middle), in: &snapshot)
        try merge(first, middle, in: &snapshot)
        try merge(middle, kept, in: &snapshot)
        #expect(snapshot.canonicalCaregiverID(first.id) == kept.id)
        let keptRecord = try #require(snapshot.record(kept.id))
        snapshot.records.removeAll { $0.id == kept.id }
        #expect(snapshot.canonicalCaregiverID(first.id) == first.id)
        snapshot.records.append(keptRecord)
        var cycle = kept
        cycle.cloudIdentity = nil
        cycle.mergedIntoID = first.id
        put(.caregiver(cycle), in: &snapshot, deleted: true)
        #expect(snapshot.canonicalCaregiverID(first.id) == first.id)
        cycle.mergedIntoID = nil
        cycle.familyID = UUID()
        put(.caregiver(cycle), in: &snapshot)
        #expect(snapshot.canonicalCaregiverID(first.id) == first.id)
    }

    @Test func concurrentAccountAcceptanceWinsAndContestedMergesDoNotRedirectRecords() throws {
        var (snapshot, duplicate, kept) = setup()
        let parent = try #require(snapshot.record(duplicate.id)?.revision)
        try merge(duplicate, kept, in: &snapshot)
        let alias = try #require(snapshot.record(duplicate.id)?.revision)
        var linked = duplicate
        linked.cloudIdentity = "late-account"
        let accepted = RecordRevision(
            id: UUID(), recordID: duplicate.id, parentIDs: [parent.id],
            value: .caregiver(linked), date: fixture.now.addingTimeInterval(-120),
            editorID: duplicate.id,
            deleted: false)
        for revisions in [[alias, parent, accepted], [accepted, alias, parent]] {
            snapshot.records.removeAll { $0.id == duplicate.id }
            snapshot.records += RevisionProjection.project(revisions)
            #expect(snapshot.caregivers.contains(linked))
            #expect(snapshot.canonicalCaregiverID(duplicate.id) == duplicate.id)
            #expect(throws: LogError.self) { try plan(duplicate, kept, in: snapshot) }
        }
        let changed = RecordRevision(
            id: UUID(), recordID: duplicate.id, parentIDs: [parent.id],
            value: .caregiver(duplicate), date: fixture.now, editorID: fixture.personID,
            deleted: false)
        snapshot.records.removeAll { $0.id == duplicate.id }
        snapshot.records += RevisionProjection.project([alias, parent, changed])
        #expect(snapshot.canonicalCaregiverID(duplicate.id) == duplicate.id)
    }

    @Test func unfinishedNursingDeletedAndConflictingTargetsBlockMerge() throws {
        let (initial, duplicate, kept) = setup()
        let child = try #require(initial.children.first)
        for person in [duplicate, kept] {
            var snapshot = initial
            let running = Activity(
                familyID: fixture.familyID, childID: child.id, occurredAt: fixture.now,
                authorID: person.id,
                payload: .nursing(
                    Nursing(
                        caregiverID: person.id,
                        segments: [NursingSegment(side: .left, start: fixture.now)])))
            put(.activity(running), in: &snapshot)
            #expect(throws: LogError.self) { try plan(duplicate, kept, in: snapshot) }
        }
        var snapshot = initial
        put(.caregiver(kept), in: &snapshot, deleted: true)
        #expect(throws: LogError.self) { try plan(duplicate, kept, in: snapshot) }
        snapshot = initial
        let index = try #require(snapshot.records.firstIndex { $0.id == kept.id })
        var branch = snapshot.records[index].revision
        branch.id = UUID()
        snapshot.records[index].heads.append(branch)
        #expect(throws: LogError.self) { try plan(duplicate, kept, in: snapshot) }
    }

    @Test func mergePayloadUsesNewVersionAndOldCaregiversStillDecode() throws {
        let (_, duplicate, kept) = setup()
        let old = RecordEnvelope(value: .caregiver(duplicate))
        #expect(old.version == 1)
        let decoded = try JSONDecoder().decode(RecordEnvelope.self, from: JSONEncoder().encode(old))
        #expect(decoded == old)
        var alias = duplicate
        alias.mergedIntoID = kept.id
        let current = RecordEnvelope(value: .caregiver(alias))
        #expect(current.version == 3)
        #expect(
            try JSONDecoder().decode(RecordEnvelope.self, from: JSONEncoder().encode(current))
                == current)
    }
}
