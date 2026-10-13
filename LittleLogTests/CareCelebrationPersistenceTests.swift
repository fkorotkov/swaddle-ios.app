import Foundation
import Testing
@testable import BabyActivityRecorder

@MainActor
struct CareCelebrationPersistenceTests {
    private func makeStore() throws -> LogStore {
        let store = LogStore(persistence: PersistenceController(inMemory: true),
                             defaults: UserDefaults(suiteName: UUID().uuidString)!, publishesWidgets: false)
        try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: true, unit: .ml)
        return store
    }
    private func pump(_ total: Decimal, store: LogStore) -> PumpSession {
        PumpSession(familyID: store.snapshot.family!.id, motherID: store.caregiverID,
                    occurredAt: .now.addingTimeInterval(-60), authorID: store.caregiverID,
                    totalML: total, unit: .ml)
    }

    @Test func onlyCommittedNewRecordsCelebrateAndUndoRemovesCelebration() throws {
        let store = try makeStore()
        try store.save(.pumping(pump(100, store: store)))
        #expect(store.pumpingCelebration == nil)
        let newRecord = pump(150, store: store)
        try store.save(.pumping(newRecord))
        #expect(store.pumpingCelebration?.id == newRecord.id)
        #expect(store.claimPumpingCelebrationMotion(newRecord.id))
        #expect(!store.claimPumpingCelebrationMotion(newRecord.id))
        store.reload()
        #expect(store.pumpingCelebration?.totalML == 150)
        #expect(!store.claimPumpingCelebrationMotion(newRecord.id))
        #expect(store.snapshot.pumps.contains { $0.id == newRecord.id })
        try store.undo()
        #expect(store.pumpingCelebration == nil)
        #expect(!store.claimPumpingCelebrationMotion(newRecord.id))
        #expect(!store.snapshot.pumps.contains { $0.id == newRecord.id })
    }

    @Test func editsRestoresImportsAndCommandRetriesStayQuiet() throws {
        let store = try makeStore()
        var original = pump(100, store: store)
        try store.save(.pumping(original))
        original.totalML = 200
        try store.save(.pumping(original))
        #expect(store.pumpingCelebration == nil)
        let imported = pump(300, store: store)
        #expect(try store.importPumpingSessions([imported]) == 1)
        #expect(store.pumpingCelebration == nil)
        let command = UUID()
        let newRecord = pump(400, store: store)
        try store.save(.pumping(newRecord), commandID: command)
        #expect(store.pumpingCelebration != nil)
        store.toast = nil
        try store.save(.pumping(newRecord), commandID: command)
        #expect(store.pumpingCelebration == nil)
        try store.save(.pumping(newRecord), deleted: true)
        try store.save(.pumping(newRecord), restoring: true)
        #expect(store.pumpingCelebration == nil)
    }

    @Test func invalidSaveDoesNotCreateCelebrationOrCareRecord() throws {
        let store = try makeStore()
        try store.save(.pumping(pump(100, store: store)))
        let invalid = pump(0, store: store)
        #expect(throws: LogError.self) { try store.save(.pumping(invalid)) }
        #expect(store.pumpingCelebration == nil)
        #expect(store.snapshot.record(invalid.id) == nil)
    }

    @Test func siriRecordsCelebrateAndKeepTheSameUndoPath() throws {
        let store = try makeStore()
        try store.save(.pumping(pump(100, store: store)))
        var spoken = pump(150, store: store); spoken.source = "Siri / Shortcuts"
        try store.save(.pumping(spoken))
        store.toast = "Pumping saved"
        #expect(store.pumpingCelebration?.id == spoken.id)
        try store.undo()
        #expect(store.pumpingCelebration == nil)
        #expect(!store.snapshot.pumps.contains { $0.id == spoken.id })
    }

    @Test func birthdayReceiptSurvivesReloadAndASecondStoreOnSameDevice() throws {
        let store = try makeStore()
        var child = try #require(store.selectedChild)
        let calendar = Calendar(identifier: .gregorian)
        child.birthDate = calendar.date(byAdding: .day, value: -7, to: .now)
        try store.save(.child(child))
        let event = try #require(AgeCelebration(child: child, at: .now, calendar: calendar))
        #expect(store.claimAgeCelebration(event))
        store.reload()
        #expect(!store.claimAgeCelebration(event))
        let reopened = LogStore(persistence: store.persistence, defaults: store.defaults, publishesWidgets: false)
        #expect(!reopened.claimAgeCelebration(event))
        #expect(reopened.snapshot == store.snapshot)
    }
}
