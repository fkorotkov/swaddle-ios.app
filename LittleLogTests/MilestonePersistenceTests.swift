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
        let parents = Set(try #require(store.snapshot.record(value.id)).heads.map(\.id))
        value.note = "Second device correction"
        try store.save(.milestone(value))
        value.note = "First device correction"
        try store.save(.milestone(value), parentIDs: parents)
        #expect(store.snapshot.record(value.id)?.hasConflict == true)
        #expect(store.snapshot.record(value.id)?.heads.count == 2)
        #expect(store.history(for: value.id).count == 3)
    }
}
