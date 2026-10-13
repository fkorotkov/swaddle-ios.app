import Foundation
import CoreSpotlight
import Testing
@testable import BabyActivityRecorder

@MainActor
private final class TestSiriIndex: SiriIndexBackend {
    var documents: [String: CareSearchDocument] = [:]
    var operations: [String] = []
    var failNextWrite = false
    var pauseNextWrite = false
    private var writeStarted = false
    private var started: CheckedContinuation<Void, Never>?
    private var resume: CheckedContinuation<Void, Never>?
    func clear() async throws { operations.append("clear"); documents = [:] }
    func delete(ids: [String]) async throws {
        operations.append("delete")
        for id in ids { documents.removeValue(forKey: id) }
    }
    func index(_ additions: [CareSearchDocument], snapshot: FamilySnapshot) async throws {
        operations.append("index")
        if failNextWrite { failNextWrite = false; throw LogError.message("Test failure") }
        if pauseNextWrite, !additions.isEmpty {
            pauseNextWrite = false
            await withCheckedContinuation { continuation in
                resume = continuation; writeStarted = true; started?.resume(); started = nil
            }
        }
        for document in additions { documents[document.id] = document }
    }
    func waitForWrite() async {
        if writeStarted { return }
        await withCheckedContinuation { started = $0 }
    }
    func finishWrite() { resume?.resume(); resume = nil }
}

@MainActor
struct SiriDiscoveryTests {
    let fixture = PersistenceTests()
    func populatedStore() throws -> (LogStore, Activity) {
        let store = fixture.store()
        let child = try fixture.setup(store)
        let activity = fixture.bottle(store, child: child)
        try store.save(.activity(activity))
        return (store, activity)
    }
    @Test func initialOffStateClearsOldInstallIndexWithoutCrashing() async {
        let backend = TestSiriIndex()
        let index = SiriDiscoveryIndex(backend: backend)
        index.update(snapshot: FamilySnapshot())
        await index.flush()
        #expect(index.status == "Care history stays in Swaddle")
        #expect(backend.operations.first == "clear")
    }
    @Test func revisionsDeletionAndChildDeletionUpdateIndex() async throws {
        let (store, entry) = try populatedStore()
        let backend = TestSiriIndex()
        let coordinator = SiriDiscoveryIndex(backend: backend)
        coordinator.update(snapshot: store.snapshot); await coordinator.flush()
        let id = CareContentID(familyID: entry.familyID, recordID: entry.id).rawValue
        #expect(backend.documents[id]?.content.contains("120 mL total") == true)
        var changed = entry
        changed.payload = .bottle(Bottle(milkML: 60, formulaML: 15, unit: .ml))
        try store.save(.activity(changed))
        coordinator.update(snapshot: store.snapshot); await coordinator.flush()
        #expect(backend.documents[id]?.content.contains("75 mL total") == true)
        try store.delete(try #require(store.snapshot.record(entry.id)))
        coordinator.update(snapshot: store.snapshot); await coordinator.flush()
        #expect(backend.documents.isEmpty)
        let newEntry = fixture.bottle(store, child: try #require(store.selectedChild))
        try store.save(.activity(newEntry))
        coordinator.update(snapshot: store.snapshot); await coordinator.flush()
        try store.delete(try #require(store.snapshot.record(entry.childID)))
        coordinator.update(snapshot: store.snapshot); await coordinator.flush()
        #expect(backend.documents.isEmpty)
    }
    @Test func optOutDuringInFlightWriteFinishesWithAnEmptyIndex() async throws {
        let (store, _) = try populatedStore()
        let backend = TestSiriIndex()
        let coordinator = SiriDiscoveryIndex(backend: backend)
        backend.pauseNextWrite = true
        coordinator.update(snapshot: store.snapshot)
        await backend.waitForWrite()
        coordinator.update(snapshot: FamilySnapshot())
        backend.finishWrite()
        await coordinator.flush()
        #expect(backend.documents.isEmpty)
        #expect(coordinator.status == "Care history stays in Swaddle")
    }
    @Test func newFamilyClearsPreviousRecordsAndExplicitReindexRebuilds() async throws {
        let (first, _) = try populatedStore(), (second, _) = try populatedStore()
        let backend = TestSiriIndex()
        let index = SiriDiscoveryIndex(backend: backend)
        index.update(snapshot: first.snapshot); await index.flush()
        index.update(snapshot: second.snapshot); await index.flush()
        #expect(backend.documents.values.allSatisfy { $0.key.familyID == second.snapshot.family?.id })
        #expect(backend.operations.filter { $0 == "clear" }.count == 2)
        backend.documents = [:]
        index.update(snapshot: second.snapshot, force: true); await index.flush()
        #expect(backend.documents.count == 1)
    }
    @Test func failedIndexWriteClearsContentAndCanRetry() async throws {
        let (store, _) = try populatedStore()
        let backend = TestSiriIndex()
        let index = SiriDiscoveryIndex(backend: backend)
        backend.failNextWrite = true
        index.update(snapshot: store.snapshot); await index.flush()
        #expect(backend.documents.isEmpty)
        #expect(index.status.contains("retry"))
        index.update(snapshot: store.snapshot); await index.flush()
        #expect(backend.documents.count == 1)
    }
    @available(iOS 27, *)
    @Test func discoveryDefaultsOnAndDeepLinksCheckCurrentAccess() throws {
        let (store, entry) = try populatedStore()
        let id = CareContentID(familyID: entry.familyID, recordID: entry.id).rawValue
        #expect(store.siriDiscoveryEnabled)
        try SiriContentAccess.validate(store)
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: id]
        store.openSearchActivity(activity)
        #expect(store.siriNavigation?.destination == .record(id))
        try store.setSiriDiscoveryEnabled(false)
        #expect(throws: LogError.self) { try SiriContentAccess.validate(store) }
        #expect(store.siriNavigation == nil)
        store.openSearchActivity(activity)
        #expect(store.siriNavigation == nil)
        try store.setSiriDiscoveryEnabled(true)
        try store.delete(try #require(store.snapshot.record(entry.id)))
        store.openSearchActivity(activity)
        #expect(store.siriNavigation == nil)
        #expect(throws: LogError.self) { try SiriContentAccess.note(id, in: store) }
    }
    @available(iOS 27, *)
    @Test func explicitOptOutSurvivesReloadAndReopeningTheFamily() throws {
        let (store, _) = try populatedStore()
        try store.setSiriDiscoveryEnabled(false)
        store.reload()
        #expect(!store.siriDiscoveryEnabled)
        let reopened = LogStore(persistence: store.persistence, defaults: store.defaults, publishesWidgets: false)
        #expect(!reopened.siriDiscoveryEnabled)
        #expect(throws: LogError.self) { try SiriContentAccess.validate(reopened) }
        try reopened.setSiriDiscoveryEnabled(true)
        reopened.reload()
        #expect(reopened.siriDiscoveryEnabled)
    }
    @available(iOS 27, *)
    @Test func discoveryRequiresAFamilyAndOptOutIsScopedToThatFamily() throws {
        let store = fixture.store()
        #expect(!store.siriDiscoveryEnabled)
        #expect(throws: LogError.self) { try store.setSiriDiscoveryEnabled(true) }
        store.defaults.set(false, forKey: "siri.discovery.\(UUID().uuidString)")
        _ = try fixture.setup(store)
        #expect(store.siriDiscoveryEnabled)
    }
    @available(iOS 27, *)
    @Test func spokenCareNoteCreatesOnlyTextAndSupportsOneChildWithoutAName() throws {
        let (store, entry) = try populatedStore()
        try store.setSiriDiscoveryEnabled(true)
        let note = try SiriCareNoteWriter.save(name: "Evening observation", content: "Had 90 mL and a wet diaper.", childID: nil, store: store)
        #expect(note.childID == entry.childID)
        #expect(note.payload == .careNote)
        #expect(note.note == "Evening observation\nHad 90 mL and a wet diaper.")
        #expect(store.snapshot.activities.filter { $0.payload.kind == .bottle }.count == 1)
        #expect(store.snapshot.activities.filter { $0.payload.kind == .diaper }.isEmpty)
        let id = CareContentID(familyID: note.familyID, recordID: note.id).rawValue
        #expect(try SiriContentAccess.note(id, in: store).isCareNote)
        let bottleID = CareContentID(familyID: entry.familyID, recordID: entry.id).rawValue
        #expect(throws: LogError.self) { try SiriContentAccess.note(bottleID, in: store) }
    }
    @available(iOS 27, *)
    @Test func careNoteRejectsAmbiguousOrDeletedChildAndDisabledAccessWithoutWriting() throws {
        let (store, first) = try populatedStore()
        try store.setSiriDiscoveryEnabled(false)
        #expect(throws: LogError.self) { try SiriCareNoteWriter.save(name: "Hello", content: nil, childID: nil, store: store) }
        try store.setSiriDiscoveryEnabled(true)
        let sibling = ChildProfile(familyID: first.familyID, name: "Jamie")
        try store.save(.child(sibling))
        #expect(throws: LogError.needsChild) { try SiriCareNoteWriter.save(name: "Hello", content: nil, childID: nil, store: store) }
        #expect(throws: LogError.self) { try SiriCareNoteWriter.save(name: "Hello", content: nil, childID: UUID(), store: store) }
        #expect(throws: LogError.self) { try SiriCareNoteWriter.save(name: "  ", content: "\n", childID: sibling.id, store: store) }
        #expect(store.snapshot.activities.count == 1)
        try store.delete(try #require(store.snapshot.record(first.childID)))
        #expect(throws: LogError.self) { try SiriCareNoteWriter.save(name: "Hello", content: nil, childID: first.childID, store: store) }
        #expect(store.snapshot.activities.isEmpty)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27))
    func olderOSKeepsUnsupportedDiscoveryOffWithoutChangingCareRecords() throws {
        let (store, entry) = try populatedStore()
        #expect(!store.siriDiscoveryEnabled)
        #expect(throws: LogError.self) { try store.setSiriDiscoveryEnabled(true) }
        #expect(throws: LogError.self) { try SiriContentAccess.validate(store) }
        #expect(store.snapshot.activities.map(\.id) == [entry.id])
    }
}
