import Foundation
import Testing
import UIKit
@testable import BabyActivityRecorder

@MainActor
struct MilestonePersistenceTests {
    @Test func allMilestoneStatusAndDomainSymbolsAreAvailable() {
        for symbol in MilestoneStatus.allCases.map(\.symbol) + MilestoneDomain.allCases.map(\.symbol) {
            #expect(UIImage(systemName: symbol) != nil)
        }
    }
    @Test func checkInsSurviveReloadEditDeleteRestoreAndUndo() throws {
        let persistence = PersistenceController(inMemory: true)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = LogStore(persistence: persistence, defaults: defaults, publishesWidgets: false)
        try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml)
        let child = try #require(store.selectedChild)
        let skill = try #require(MilestoneCatalog.skill("cdc-2-smilestalk2"))
        let first = MilestoneObservation(familyID: child.familyID, childID: child.id,
            skillID: skill.id, sourceVersion: skill.sourceVersion, skillTitle: skill.title,
            status: .seen, note: "Morning smile", authorID: store.caregiverID)
        let command = UUID()
        try store.save(.milestone(first), commandID: command)
        try store.save(.milestone(first), commandID: command)
        #expect(store.snapshot.milestoneObservations == [first])
        #expect(store.history(for: first.id).count == 1)
        let reopened = LogStore(persistence: persistence, defaults: defaults, publishesWidgets: false)
        #expect(reopened.snapshot.milestoneObservations == [first])
        var correction = first; correction.note = "Afternoon smile"
        try reopened.save(.milestone(correction))
        #expect(reopened.snapshot.milestoneObservations == [correction])
        #expect(reopened.history(for: first.id).count == 2)
        #expect(reopened.history(for: first.id).contains { $0.value == .milestone(first) })
        let record = try #require(reopened.snapshot.record(first.id))
        try reopened.delete(record)
        #expect(reopened.snapshot.milestoneObservations.isEmpty)
        #expect(throws: LogError.self) { try reopened.save(.milestone(correction)) }
        try reopened.save(.milestone(correction), restoring: true)
        #expect(reopened.snapshot.milestoneObservations == [correction])
        var next = first; next.id = UUID(); next.status = .unsure; next.note = "New check-in"
        try reopened.save(.milestone(next))
        #expect(reopened.snapshot.milestoneObservations.count == 2)
        try reopened.undo()
        #expect(reopened.snapshot.milestoneObservations == [correction])
        #expect(reopened.snapshot.record(next.id)?.isDeleted == true)
        #expect(reopened.snapshot.activities.isEmpty && reopened.snapshot.pumps.isEmpty)
    }

    @Test func anOpenDraftCannotSilentlyOverwriteARemoteCorrection() throws {
        let store = LogStore(persistence: PersistenceController(inMemory: true),
            defaults: UserDefaults(suiteName: UUID().uuidString)!, publishesWidgets: false)
        try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml)
        let child = try #require(store.selectedChild)
        let skill = MilestoneCatalog.motorSkills[0]
        var value = MilestoneObservation(familyID: child.familyID, childID: child.id,
            skillID: skill.id, sourceVersion: skill.sourceVersion, skillTitle: skill.title,
            status: .unsure, authorID: store.caregiverID)
        try store.save(.milestone(value))
        let draft = MilestoneCheckInDraft(route: .init(child: child, skill: skill, observation: value), snapshot: store.snapshot)
        #expect(!draft.isDirty)
        let commandID = draft.commandID
        draft.note = "First device correction"
        draft.firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        draft.includeDate = true
        draft.status = .seen
        #expect(draft.isDirty)
        value.note = "Second device correction"
        try store.save(.milestone(value))
        // Both display columns use this same draft. A refresh must not reseed its
        // input or move its opening heads forward to the other caregiver's edit.
        #expect(draft.note == "First device correction")
        #expect(draft.commandID == commandID)
        value.note = draft.note
        value.status = try #require(draft.status)
        value.firstNoticedAt = draft.firstDate
        try store.save(.milestone(value), parentIDs: draft.parents, commandID: draft.commandID)
        #expect(store.snapshot.record(value.id)?.hasConflict == true)
        #expect(store.snapshot.record(value.id)?.heads.count == 2)
        #expect(store.history(for: value.id).count == 3)
    }
}
