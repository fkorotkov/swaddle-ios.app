import Foundation
import Testing
@testable import BabyActivityRecorder

@MainActor
struct ProfileAppearancePersistenceTests {
    @Test func sharedProfilesRetainSexAndCareHistoryAfterReload() throws {
        let store = LogStore(persistence: PersistenceController(inMemory: true),
            defaults: UserDefaults(suiteName: UUID().uuidString)!, publishesWidgets: false)
        try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml, gender: .boy)
        let child = try #require(store.selectedChild)
        var me = try #require(store.snapshot.caregivers.first { $0.id == store.caregiverID })
        me.sex = .female
        try store.save(.child(child)); try store.save(.caregiver(me))
        let bottle = Activity(familyID: child.familyID, childID: child.id, occurredAt: .now,
            authorID: me.id, payload: .bottle(Bottle(milkML: 120, formulaML: 0, unit: .ml)))
        try store.save(.activity(bottle), rememberBottle: true)
        let reopened = LogStore(persistence: store.persistence, defaults: store.defaults, publishesWidgets: false)
        #expect(reopened.selectedChild == child)
        #expect(reopened.snapshot.caregivers.first { $0.id == me.id } == me)
        #expect(reopened.selectedChild?.effectiveGrowthReferenceSex == .male)
        #expect(reopened.snapshot.activities == [bottle])
        me.sex = nil
        try reopened.save(.caregiver(me)); try reopened.save(.child(child)); reopened.reload()
        #expect(reopened.snapshot.caregivers.first { $0.id == me.id }?.sex == nil)
        #expect(reopened.selectedChild == child)
        #expect(reopened.previousBottle(childID: child.id)?.totalML == 120)
        #expect(reopened.snapshot.activities == [bottle])
    }

    @Test func mergeAndSeparationKeepSexAndCareHistory() throws {
        let store = LogStore(persistence: PersistenceController(inMemory: true),
            defaults: UserDefaults(suiteName: UUID().uuidString)!, publishesWidgets: false)
        try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml)
        let family = try #require(store.snapshot.family)
        let source = Caregiver(familyID: family.id, name: "Alex", isMother: true, sex: .female)
        let kept = Caregiver(familyID: family.id, name: "Alex linked", cloudIdentity: "linked")
        try store.save(.caregiver(source)); try store.save(.caregiver(kept))
        let plan = try CaregiverMergeRules.plan(sourceID: source.id, destinationID: kept.id,
            in: store.snapshot, actorID: store.caregiverID, canEdit: store.canEdit)
        try store.mergeCaregivers(plan); store.reload()
        let merged = try #require(store.snapshot.caregivers.first { $0.id == kept.id })
        #expect(merged.sex == .female)
        #expect(merged.cloudIdentity == "linked")
        try store.separateCaregiver(source.id); store.reload()
        #expect(store.snapshot.caregivers.first { $0.id == source.id }?.sex == source.sex)
    }
}
