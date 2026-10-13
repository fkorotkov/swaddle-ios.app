import Foundation
import CoreData
import CloudKit
import Testing
@testable import BabyActivityRecorder

@MainActor
struct PersistenceTests {
    func store() -> LogStore {
        LogStore(persistence: PersistenceController(inMemory: true), defaults: UserDefaults(suiteName: UUID().uuidString)!, publishesWidgets: false)
    }
    func setup(_ store: LogStore) throws -> ChildProfile {
        try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: true, unit: .ml)
        return try #require(store.selectedChild)
    }
    func bottle(_ store: LogStore, child: ChildProfile, milk: Decimal = 90, formula: Decimal = 30) -> Activity {
        Activity(familyID: child.familyID, childID: child.id, occurredAt: .now.addingTimeInterval(-60), authorID: store.caregiverID, payload: .bottle(Bottle(milkML: milk, formulaML: formula, unit: .ml)))
    }
    @Test func cloudNotificationsNeverWaitForMainThread() throws {
        let store = store()
        _ = try setup(store)
        let names: [Notification.Name] = [
            .NSPersistentStoreRemoteChange,
            NSPersistentCloudKitContainer.eventChangedNotification,
            .CKAccountChanged
        ]
        withExtendedLifetime(store) {
            for name in names {
                let posted = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    NotificationCenter.default.post(name: name, object: nil)
                    posted.signal()
                }
                // Deliberately hold the main actor, as Core Data's share setup
                // can do. Posting must finish without running the UI update.
                #expect(posted.wait(timeout: .now() + 1) == .success,
                        "Posting \(name.rawValue) must not synchronously wait for the main thread.")
            }
        }
    }
    @Test func savesAtomicallyAndRetryDoesNotDuplicate() throws {
        let store = store(), command = UUID()
        let child = try setup(store)
        let entry = bottle(store, child: child)
        try store.save(.activity(entry), commandID: command, rememberBottle: true)
        try store.save(.activity(entry), commandID: command, rememberBottle: true)
        #expect(store.snapshot.activities.count == 1)
        #expect(store.history(for: entry.id).count == 1)
        #expect(store.previousBottle(childID: child.id)?.milkML == 90)
        let invalid = bottle(store, child: child, milk: -1)
        #expect(throws: LogError.self) { try store.save(.activity(invalid), rememberBottle: true) }
        #expect(store.snapshot.activities.count == 1)
        #expect(store.previousBottle(childID: child.id)?.milkML == 90)
    }
  @Test func syncDiagnosticOmitsFamilyNamesIdentifiersAndCareContents() throws {
    let store = store()
    let child = try setup(store)
    var feed = bottle(store, child: child)
    feed.note = "Private care observation"
    try store.save(.activity(feed))
    store.persistence.migrationStage = "Verifying 3 saved records"
    store.persistence.legacySyncFailure = "NSCocoaErrorDomain / 134060"
    let text = store.syncDiagnostic
    #expect(text.contains("NSCocoaErrorDomain / 134060"))
    #expect(text.contains("Verifying 3 saved records"))
    #expect(text.contains("Caregiver profiles: 1"))
    for privateValue in [
      child.name, store.myName, child.id.uuidString, child.familyID.uuidString,
      store.caregiverID.uuidString, feed.id.uuidString, feed.note,
    ] {
      #expect(!text.contains(privateValue))
    }
    #expect(!store.syncNeedsAttention)
  }
    @Test func preferencesAreIsolatedAndEditsDoNotChangeDefaults() throws {
        let store = store()
        let child = try setup(store)
        let sibling = ChildProfile(familyID: child.familyID, name: "Jamie")
        try store.save(.child(sibling))
        var entry = bottle(store, child: child)
        try store.save(.activity(entry), rememberBottle: true)
        #expect(store.previousBottle(childID: sibling.id) == nil)
        entry.payload = .bottle(Bottle(milkML: 150, formulaML: 0, unit: .ml))
        try store.save(.activity(entry), rememberBottle: true)
        #expect(store.previousBottle(childID: child.id)?.milkML == 90)
        #expect(store.previousBottle(childID: child.id)?.formulaML == 30)
    }
    @Test func undoRestoresRememberedBottleAndFirstFeedReturnsToBlank() throws {
        let store = store()
        let child = try setup(store)
        try store.save(.activity(bottle(store, child: child)), rememberBottle: true)
        try store.undo()
        #expect(store.snapshot.activities.isEmpty)
        #expect(store.previousBottle(childID: child.id) == nil)

        try store.save(.activity(bottle(store, child: child)), rememberBottle: true)
        let adjusted = bottle(store, child: child, milk: 105, formula: 45)
        try store.save(.activity(adjusted), rememberBottle: true)
        #expect(store.previousBottle(childID: child.id)?.milkML == 105)
        #expect(throws: LogError.self) { try store.save(.activity(bottle(store, child: child, milk: -1)), rememberBottle: true) }
        try store.undo()
        #expect(store.snapshot.activities.count == 1)
        #expect(store.snapshot.record(adjusted.id)?.isDeleted == true)
        #expect(store.previousBottle(childID: child.id)?.milkML == 90)
        #expect(store.previousBottle(childID: child.id)?.formulaML == 30)
    }
    @Test func undoKeepsSiblingDefaultsAndUnrelatedCreationsDoNotClearThem() throws {
        let store = store()
        let child = try setup(store)
        let sibling = ChildProfile(familyID: child.familyID, name: "Jamie")
        try store.save(.child(sibling))
        try store.save(.activity(bottle(store, child: child)), rememberBottle: true)
        try store.save(.activity(bottle(store, child: sibling, milk: 60, formula: 0)), rememberBottle: true)
        try store.save(.activity(bottle(store, child: child, milk: 105)), rememberBottle: true)
        try store.undo()
        #expect(store.previousBottle(childID: child.id)?.milkML == 90)
        #expect(store.previousBottle(childID: sibling.id)?.milkML == 60)

        try store.save(.activity(bottle(store, child: child, milk: 120)), rememberBottle: true)
        let diaper = Activity(familyID: child.familyID, childID: child.id, occurredAt: .now, authorID: store.caregiverID, payload: .diaper(Diaper(pee: true, poo: false)))
        try store.save(.activity(diaper))
        try store.undo()
        #expect(store.snapshot.record(diaper.id)?.isDeleted == true)
        #expect(store.previousBottle(childID: child.id)?.milkML == 120)
        #expect(store.previousBottle(childID: sibling.id)?.milkML == 60)
    }
    @Test func childDeletionPreservesSiblingAndMother() throws {
        let store = store()
        let child = try setup(store)
        let sibling = ChildProfile(familyID: child.familyID, name: "Jamie")
        try store.save(.child(sibling))
        try store.save(.activity(bottle(store, child: child)))
        try store.save(.activity(bottle(store, child: sibling)))
        try store.save(.pumping(PumpSession(familyID: child.familyID, motherID: store.caregiverID, occurredAt: .now, authorID: store.caregiverID, totalML: 105, unit: .ml)))
        try store.delete(try #require(store.snapshot.record(child.id)))
        #expect(store.snapshot.children.map(\.id) == [sibling.id])
        #expect(store.snapshot.activities.count == 1)
        #expect(store.snapshot.activities[0].childID == sibling.id)
        #expect(store.snapshot.pumps.count == 1)
        #expect(store.snapshot.pumps[0].totalML == 105)
    }
    @Test func concurrentEditsRetainHistoryAndDeleteWins() throws {
        let store = store()
        let child = try setup(store)
        var entry = bottle(store, child: child)
        try store.save(.activity(entry))
        let original = try #require(store.snapshot.record(entry.id))
        let parents = Set(original.heads.map(\.id))
        entry.payload = .bottle(Bottle(milkML: 60, formulaML: 0, unit: .ml))
        try store.save(.activity(entry), parentIDs: parents)
        try store.save(.activity(entry), parentIDs: parents, deleted: true)
        let result = try #require(store.snapshot.record(entry.id))
        #expect(result.hasConflict && result.isDeleted)
        #expect(store.history(for: entry.id).count == 3)
        #expect(store.snapshot.activities.isEmpty)
        #expect(throws: LogError.self) { try store.save(.activity(entry), parentIDs: parents) }
    }
    @Test func diskReopenRestoresTimerAndRememberedBottle() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = LogStore(persistence: PersistenceController(directory: directory), defaults: defaults, publishesWidgets: false)
        let child = try setup(store)
        try store.save(.activity(bottle(store, child: child)), rememberBottle: true)
        var nursing = Nursing(caregiverID: store.caregiverID)
        let start = Date.now.addingTimeInterval(-120)
        nursing.start(.left, at: start)
        try store.save(.activity(Activity(familyID: child.familyID, childID: child.id, occurredAt: start, authorID: store.caregiverID, payload: .nursing(nursing))))
        let reopened = LogStore(persistence: PersistenceController(directory: directory), defaults: defaults, publishesWidgets: false)
        #expect(reopened.isReady)
        #expect(reopened.selectedChild?.id == child.id)
        #expect(reopened.previousBottle(childID: child.id)?.milkML == 90)
        let timer = try #require(reopened.snapshot.activities.first { !$0.payload.isComplete })
        if case .nursing(let restored) = timer.payload {
            #expect(restored.activeSide == .left)
            #expect(restored.duration(at: .now) >= 120)
        }
    }
    @Test func explicitRecoveryRestoresWithoutChangingBottleDefaults() throws {
        let store = store()
        let child = try setup(store)
        let entry = bottle(store, child: child)
        try store.save(.activity(entry), rememberBottle: true)
        let original = try #require(store.snapshot.record(entry.id))
        try store.delete(original)
        let tombstone = try #require(store.snapshot.record(entry.id))
        #expect(store.snapshot.activities.isEmpty)
        try store.resolve(tombstone, using: original.revision)
        #expect(store.snapshot.activities.count == 1)
        #expect(store.snapshot.record(entry.id)?.hasConflict == false)
        #expect(store.history(for: entry.id).count == 3)
        #expect(store.previousBottle(childID: child.id)?.milkML == 90)
        try store.delete(try #require(store.snapshot.record(child.id)))
        #expect(store.snapshot.activities.isEmpty)
        let deletedChild = try #require(store.snapshot.record(child.id))
        let childVersion = try #require(store.history(for: child.id).last { !$0.deleted })
        try store.resolve(deletedChild, using: childVersion)
        #expect(store.snapshot.activities.count == 1)
    }
    @Test func deletingFamilyRequiresOwnerAndCascadesAllRecords() throws {
        let store = store()
        let child = try setup(store)
        let owner = store.caregiverID
        try store.save(.activity(bottle(store, child: child)), rememberBottle: true)
        try store.save(.pumping(PumpSession(familyID: child.familyID, motherID: owner, occurredAt: .now, authorID: owner, totalML: 105, unit: .ml)))
        store.defaults.set(UUID().uuidString, forKey: "caregiverID")
        #expect(throws: LogError.self) { try store.deleteFamily() }
        #expect(store.snapshot.family != nil)
        store.defaults.set(owner.uuidString, forKey: "caregiverID")
        try store.deleteFamily()
        #expect(store.snapshot.family == nil && store.snapshot.activities.isEmpty && store.snapshot.pumps.isEmpty)
        #expect(store.undoID == nil && store.selectedChildID == nil)
        for entity in ["FamilyRoot", "Revision", "PrivatePreference"] {
            #expect(try store.persistence.context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entity)) == 0)
        }
    }
    @Test func importingNurseReportIsAtomicIdempotentAndUndoableAsOneBatch() throws {
        let store = store()
        let child = try setup(store)
        try store.save(.activity(bottle(store, child: child, milk: 90, formula: 30)), rememberBottle: true)
        let day = Calendar.current.date(byAdding: .day, value: -2, to: .now)!
        let rows = try CareNoteParser.parse(CareNoteParser.sample, firstDay: day, timeZone: .current, defaultUnit: .ml)
        let entries = try rows.map { try $0.activity(child: child, authorID: store.caregiverID) }
        #expect(try store.importActivities(entries) == 7)
        #expect(try store.importActivities(entries) == 0)
        #expect(store.snapshot.activities.count == 8)
        #expect(store.previousBottle(childID: child.id)?.milkML == 90)
        #expect(store.previousBottle(childID: child.id)?.formulaML == 30)
        try store.undo()
        #expect(store.snapshot.activities.count == 1)
        #expect(entries.allSatisfy { store.snapshot.record($0.id)?.isDeleted == true })
        #expect(store.previousBottle(childID: child.id)?.milkML == 90)
    }
    @Test func invalidImportWritesNothingAndSimilarityIsChildSpecific() throws {
        let store = store()
        let child = try setup(store)
        let valid = bottle(store, child: child)
        var invalid = bottle(store, child: child, milk: -1)
        invalid.source = "Text import"
        #expect(throws: LogError.self) { try store.importActivities([valid, invalid]) }
        #expect(store.snapshot.activities.isEmpty && store.previousBottle(childID: child.id) == nil)
        let row = CareImportDraft(kind: .bottle, source: "90 mL milk + 30 mL formula", sourceLine: 1, block: 0, timestamp: valid.occurredAt, unit: .ml, milk: "90", formula: "30")
        #expect(row.resembles(valid, child: child, authorID: store.caregiverID))
        let sibling = ChildProfile(familyID: child.familyID, name: "Jamie")
        #expect(!row.resembles(valid, child: sibling, authorID: store.caregiverID))
    }
    @Test func jsonLinesImportRetainsIdentitiesAndNotesRejectsRacesAndUndoesTogether() throws {
        let store = store()
        let child = try setup(store)
        try store.save(.activity(bottle(store, child: child, milk: 120, formula: 0)), rememberBottle: true)
        let text = JSONLinesCareImport.example.replacingOccurrences(of: #""type":"feed""#, with: #""id":"feed-1","source":"example","type":"feed""#) + "\n" + JSONLinesCareImport.unknownExample
        func entries() throws -> [Activity] {
            try CareNoteParser.parse(text, firstDay: .now, timeZone: .current, defaultUnit: .oz)
                .map { try $0.activity(child: child, authorID: store.caregiverID) }
        }
        let first = try entries()
        #expect(try store.importActivities(first) == 2)
        store.reload()
        #expect(store.snapshot.activities.count == 3)
        #expect(store.snapshot.activities.contains { $0.importIdentity == ImportIdentity(source: "example", id: "feed-1") && $0.note.hasPrefix("Finished bottle.") })
        #expect(try store.importActivities(first) == 0)
        #expect(throws: LogError.self) { try store.importActivities(entries()) }
        #expect(store.snapshot.activities.count == 3)
        #expect(store.previousBottle(childID: child.id)?.milkML == 120)
        try store.undo()
        #expect(store.snapshot.activities.count == 1)
        #expect(try store.importActivities(entries()) == 2)
        #expect(store.snapshot.activities.count == 3)
    }
    @Test func structuredImportPersistsUnknownTotalsAndPreservesBottleDefaults() throws {
        let store = store()
        let child = try setup(store)
        try store.save(.activity(bottle(store, child: child, milk: 90, formula: 30)), rememberBottle: true)
        let text = """
        Timezone: America/New_York. BM = breast milk. All feeds are bottles.
        2026-05-10 08:00 | Mixed BM/formula | 75 ml | Breast milk 60 ml; formula 15 ml.
        2026-05-10 11:00 | Mixed BM/formula | 95 ml | Split not recorded.
        """
        let rows = try CareNoteParser.parse(text, firstDay: .now, timeZone: .current, defaultUnit: .oz)
        let entries = try rows.map { try $0.activity(child: child, authorID: store.caregiverID) }
        #expect(try store.importActivities(entries) == 2)
        store.reload()
        #expect(store.isReady && store.errorMessage == nil)
        let imported = store.snapshot.activities.filter { $0.source == "Text import" }
        let summary = ActivitySummary(activities: imported, childID: child.id)
        #expect(summary.totalML == 170 && summary.unknownML == 95 && summary.bottles == 2)
        #expect(imported.allSatisfy { $0.timeZoneIdentifier == "America/New_York" })
        #expect(store.previousBottle(childID: child.id)?.milkML == 90)
        #expect(store.previousBottle(childID: child.id)?.formulaML == 30)
        #expect(try store.importActivities(entries) == 0)
        try store.undo()
        #expect(store.snapshot.activities.count == 1)
    }
}
