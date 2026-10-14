import CoreData
import Foundation
import Testing
@testable import BabyActivityRecorder

@MainActor
struct DemoSessionTests {
    @Test func demoEditsCannotChangeRealRecordsPreferencesWidgetsOrSearch() async throws {
        let realSuite = "test.real.\(UUID())", demoSuite = "test.demo.\(UUID())"
        let realDefaults = try #require(UserDefaults(suiteName: realSuite))
        defer {
            realDefaults.removePersistentDomain(forName: realSuite)
            UserDefaults(suiteName: demoSuite)?.removePersistentDomain(forName: demoSuite)
        }
        let real = LogStore(persistence: PersistenceController(inMemory: true), defaults: realDefaults, publishesWidgets: false)
        try real.createFamily(childName: "Real family", caregiverName: "Real caregiver", mother: false, unit: .ml)
        let original = real.snapshot
        let preferences = NSDictionary(dictionary: realDefaults.persistentDomain(forName: realSuite) ?? [:])
        let widgets = NSDictionary(dictionary: WidgetCache.defaults.persistentDomain(forName: PersistenceController.appGroup) ?? [:])

        let session = DemoSession(defaultsName: demoSuite)
        try session.start()
        let demo = try #require(session.store)
        #expect(demo.isDemo && demo.isReady && demo.canEdit)
        #expect(!demo.persistence.cloudEnabled && !demo.persistence.usesCKSyncEngine)
        #expect(demo.persistence.container.persistentStoreCoordinator.persistentStores.allSatisfy { $0.type == NSInMemoryStoreType })
        #expect(demo.persistence !== real.persistence)
        let child = try #require(demo.selectedChild)
        let record = Activity(familyID: child.familyID, childID: child.id, occurredAt: .now,
                              authorID: demo.caregiverID, payload: .diaper(Diaper(pee: true, poo: true)))
        try demo.save(.activity(record))
        #expect(demo.snapshot.activities.contains { $0.id == record.id })
        try demo.undo()
        #expect(!demo.snapshot.activities.contains { $0.id == record.id })
        demo.volumeUnit = .oz
        demo.defaults.set(LengthUnit.inch.rawValue, forKey: LengthUnit.preferenceKey)
        try demo.setSiriDiscoveryEnabled(true)
        await demo.reindexSiriDiscovery()
        await demo.checkAccount()
        await demo.syncCloud()
        #expect(!demo.siriDiscoveryEnabled)
        #expect(demo.pendingUploadCount == 0 && demo.lastUpload == nil && demo.lastSync == nil)
        real.reload()
        #expect(real.snapshot == original)
        #expect(preferences == NSDictionary(dictionary: realDefaults.persistentDomain(forName: realSuite) ?? [:]))
        #expect(widgets == NSDictionary(dictionary: WidgetCache.defaults.persistentDomain(forName: PersistenceController.appGroup) ?? [:]))
        session.exit()
        #expect(session.store == nil)
        let remainingDemoPreferences = UserDefaults(suiteName: demoSuite)?.persistentDomain(forName: demoSuite) ?? [:]
        #expect(remainingDemoPreferences.isEmpty)
    }

    @Test func exitAndFreshSessionDiscardTheDemo() throws {
        let suite = "test.demo.\(UUID())"
        let session = DemoSession(defaultsName: suite)
        defer { session.exit() }
        try session.start()
        let first = try #require(session.store)
        let firstID = first.snapshot.family?.id
        first.volumeUnit = .oz
        session.exit()
        try session.start()
        #expect(session.store?.snapshot.family?.id != firstID)
        #expect(session.store?.volumeUnit == .ml)
        // A new process constructs this same initial state; no preference restores a demo.
        let relaunch = DemoSession(defaultsName: suite)
        #expect(relaunch.store == nil)
        #expect(session.store != nil) // Creating another owner does not erase a live scene.
    }

    @Test func seedingIsRefusedByOrdinaryStoresAndOccupiedDemos() throws {
        let suite = "test.demo.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ordinary = LogStore(persistence: PersistenceController(inMemory: true), defaults: defaults, publishesWidgets: false)
        let fixture = try DemoFamily.make()
        #expect(throws: LogError.self) { try ordinary.loadDemoFamily(fixture) }
        #expect(ordinary.snapshot.family == nil)
        let demo = LogStore(defaults: defaults, isDemo: true)
        try demo.loadDemoFamily(fixture)
        #expect(throws: LogError.self) { try demo.loadDemoFamily(fixture) }
        #expect(demo.snapshot.records.count == fixture.records.count)
    }
}
