import CloudKit
import CoreData
import Foundation
import Testing

@testable import LittleLogCore

@MainActor
struct CloudSyncMigrationRecoveryTests {
  private let fixtures = CareCloudSyncTests()

  @Test func misplacedRevisionIsCopiedIntoExistingFamilyShareAndOriginalIsRetained() throws {
    let (source, replica, root) = try fixtures.fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    _ = try fixtures.addRevision(
      source, root: root,
      value: .child(
        ChildProfile(
          familyID: try #require(root.value(forKey: "id") as? UUID), name: "Robin")))
    try replica.reconcile()
    let rootEntry = try #require(
      replica.journal.entries.values.first { $0.baseline.entity == "FamilyRoot" })
    let revision = try #require(
      replica.journal.entries.values.first { $0.baseline.entity == "Revision" })
    let remoteRoot = try fixtures.serverCopy(rootEntry.baseline)
    var orphan = revision.baseline
    orphan.id.zone = "legacy-private-zone"
    orphan.id.name = "old-revision"
    orphan = try fixtures.serverCopy(orphan)
    let share = CKShare(recordZoneID: remoteRoot.id.zoneID)
    var plan = CloudSyncMigration.Plan(journal: replica.journal)
    plan.journal.shares[CareCloudID(share.recordID, scope: .personal).key] =
      try NSKeyedArchiver.archivedData(withRootObject: share, requiringSecureCoding: true)
    let zones: Set<String> = [remoteRoot.id.zoneKey, orphan.id.zoneKey]
    let recovered = try CloudSyncMigration.resolve(
      plan, serverRecords: [remoteRoot, orphan],
      existingZones: zones, unsharedPrivateZones: [orphan.id.zoneKey])
    #expect(recovered.pendingCount == 1)
    #expect(recovered.retainedLegacyRecords == [orphan])
    #expect(
      recovered.entries[revision.baseline.id.key]?.pending?.fields == revision.baseline.fields)
    try CloudSyncMigration.verifyLocalCheckpoint(source, journal: recovered)
    try recovered.write(to: replica.journalURL)
    let restarted = CareSyncReplica(
      persistence: source,
      journal: try #require(try CareSyncJournal.read(from: replica.journalURL)),
      url: replica.journalURL)
    try restarted.receive([orphan])
    #expect(restarted.journal.incoming.isEmpty)
    #expect(restarted.journal.pendingCount == 1)
    #expect(
      try source.context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Revision"))
        == 1)
    let saved = try fixtures.serverCopy(revision.baseline)
    try restarted.acknowledge([saved], deleted: [])
    try restarted.receive([orphan, saved])
    #expect(restarted.journal.pendingCount == 0)
    #expect(
      try source.context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Revision"))
        == 1)

    // A different share, changed payload, or destination collision is never repaired by guessing.
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.resolve(
        plan, serverRecords: [remoteRoot, orphan], existingZones: zones)
    }
    var changed = orphan
    changed.fields["tombstone"] = .integer(1)
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.resolve(
        plan, serverRecords: [remoteRoot, changed], existingZones: zones,
        unsharedPrivateZones: [orphan.id.zoneKey])
    }
    #expect(throws: CareSyncError.self) { try restarted.receive([changed]) }
    var collision = saved
    collision.fields["id"] = .string(UUID().uuidString)
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.resolve(
        plan, serverRecords: [remoteRoot, orphan, collision], existingZones: zones,
        unsharedPrivateZones: [orphan.id.zoneKey])
    }
  }

  @Test func stalledExportTransfersFeedsAndMergeWithoutLosingOrDuplicatingRecords() throws {
    let (source, sender, root) = try fixtures.fixture()
    defer { try? FileManager.default.removeItem(at: sender.journalURL) }
    let familyID = try #require(root.value(forKey: "id") as? UUID)
    let ownerID = try #require(root.value(forKey: "ownerID") as? UUID)
    let child = ChildProfile(familyID: familyID, name: "Robin")
    let kept = Caregiver(familyID: familyID, name: "Alex", isMother: true)
    var duplicate = Caregiver(familyID: familyID, name: "Alex", isMother: true)
    let originalID = UUID()
    _ = try fixtures.addRevision(source, root: root, value: .child(child))
    _ = try fixtures.addRevision(source, root: root, value: .caregiver(kept))
    _ = try fixtures.addRevision(source, root: root, value: .caregiver(duplicate), id: originalID)
    try sender.reconcile()
    try fixtures.acknowledgeEverything(sender)
    let oldRecords = sender.journal.entries.values.map(\.baseline)

    // The owner's new feed and profile merge have never reached the server.
    duplicate.mergedIntoID = kept.id
    _ = try fixtures.addRevision(
      source, root: root, value: .caregiver(duplicate), parents: [originalID], deleted: true)
    let feed = Activity(
      familyID: familyID, childID: child.id, occurredAt: fixtures.date,
      authorID: ownerID, payload: .bottle(Bottle(milkML: 90, formulaML: 30, unit: .ml)))
    _ = try fixtures.addRevision(source, root: root, value: .activity(feed))
    try sender.reconcile()
    let plan = CloudSyncMigration.Plan(
      journal: sender.journal,
      localInsertURIs: Set(
        sender.journal.entries.values.filter { $0.pending != nil }.map(\.objectURI)))
    let migration = try CloudSyncMigration.resolve(
      plan, serverRecords: oldRecords,
      existingZones: Set(oldRecords.map { $0.id.zoneKey }))
    #expect(migration.pendingCount == 2)
    try CloudSyncMigration.verifyLocalCheckpoint(source, journal: migration)
    try migration.write(to: sender.journalURL)
    let recovered = CareSyncReplica(
      persistence: source,
      journal: try #require(try CareSyncJournal.read(from: sender.journalURL)),
      url: sender.journalURL)
    try recovered.reconcile()
    #expect(recovered.journal.pendingCount == 2)
    #expect(Set(recovered.journal.entries.keys) == Set(sender.journal.entries.keys))

    let receiver = PersistenceController(inMemory: true)
    let url = FileManager.default.temporaryDirectory.appending(
      path: "SwaddleHandoff-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let receiving = CareSyncReplica(
      persistence: receiver, journal: CareSyncJournal(account: "recipient"), url: url)
    func sharedCopy(_ record: CareCloudRecord) throws -> CareCloudRecord {
      var copy = record
      copy.id.scope = .shared
      copy.id.owner = "family-owner"
      // Recreate system fields for the receiving account's record identity.
      copy.systemFields = nil
      return try fixtures.serverCopy(copy)
    }
    try receiving.receive(oldRecords.map(sharedCopy))
    let family = Family(
      id: familyID, name: "Our family", timeZoneIdentifier: "America/New_York", ownerID: ownerID)
    func snapshot() throws -> FamilySnapshot {
      let objects = try receiver.context.fetch(
        NSFetchRequest<NSManagedObject>(entityName: "Revision"))
      let revisions = try objects.map { object -> RecordRevision in
        let envelope = try JSONDecoder().decode(
          RecordEnvelope.self, from: #require(object.value(forKey: "payload") as? Data))
        return RecordRevision(
          id: try #require(object.value(forKey: "id") as? UUID), recordID: envelope.value.id,
          parentIDs: try JSONDecoder().decode(
            Set<UUID>.self, from: #require(object.value(forKey: "parentIDs") as? Data)),
          value: envelope.value, date: fixtures.date, editorID: ownerID,
          deleted: object.value(forKey: "tombstone") as? Bool ?? false)
      }
      return FamilySnapshot(family: family, records: RevisionProjection.project(revisions))
    }
    #expect(try snapshot().caregivers.count == 2)
    #expect(try snapshot().activities.isEmpty)
    let uploads = try recovered.journal.entries.values.compactMap(\.pending).map(
      fixtures.serverCopy)
    try recovered.acknowledge(uploads, deleted: [])
    try receiving.receive(uploads.map(sharedCopy))
    try receiving.receive(uploads.map(sharedCopy))
    let result = try snapshot()
    #expect(result.caregivers.map(\.id) == [kept.id])
    #expect(result.activities == [feed])
    let summary = ActivitySummary(
      activities: result.activities, childID: child.id,
      start: fixtures.date.addingTimeInterval(-86400), end: fixtures.date)
    #expect(summary.bottles == 1)
    #expect(summary.milkML == 90 && summary.formulaML == 30)
    #expect(recovered.journal.pendingCount == 0)
  }

  @Test func missingFamilyZoneOrInsertHistoryNeverManufacturesRecords() throws {
    let (source, replica, root) = try fixtures.fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    _ = try fixtures.addRevision(
      source, root: root,
      value: .child(
        ChildProfile(familyID: try #require(root.value(forKey: "id") as? UUID), name: "Robin")))
    try replica.reconcile()
    let rootEntry = try #require(
      replica.journal.entries.values.first { $0.baseline.entity == "FamilyRoot" })
    let remoteRoot = try fixtures.serverCopy(rootEntry.baseline)
    var plan = CloudSyncMigration.Plan(journal: replica.journal)
    let zones: Set<String> = [remoteRoot.id.zoneKey]
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.resolve(plan, serverRecords: [remoteRoot], existingZones: zones)
    }
    plan.localInsertURIs = Set(replica.journal.entries.values.map(\.objectURI))
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.resolve(plan, serverRecords: [], existingZones: zones)
    }
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.resolve(plan, serverRecords: [remoteRoot], existingZones: [])
    }
    var changed = remoteRoot
    changed.fields["timeZone"] = .string("America/Chicago")
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.resolve(plan, serverRecords: [changed], existingZones: zones)
    }
  }

  @Test func unmappedRecordsRecoverExistingCloudIDsAndFamilyRelationship() throws {
    let (source, replica, root) = try fixtures.fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    _ = try fixtures.addRevision(
      source, root: root,
      value: .child(
        ChildProfile(familyID: try #require(root.value(forKey: "id") as? UUID), name: "Robin")))
    try replica.reconcile()
    let rootID = try #require(
      replica.journal.entries.values.first { $0.baseline.entity == "FamilyRoot" }?.baseline.id)
    let uri = root.objectID.uriRepresentation().absoluteString
    let plan = try CloudSyncMigration.capturePlan(
      source, account: "test-account", rootZones: [uri: rootID])
    #expect(plan.unmappedURIs.count == 2)
    let remote = try replica.journal.entries.values.map { entry -> CareCloudRecord in
      var record = entry.baseline
      record.id.name = record.entity == "FamilyRoot" ? "legacy-root" : "legacy-revision"
      if record.entity == "Revision" { record.fields["family"] = .string("legacy-root") }
      return try fixtures.serverCopy(record)
    }
    let recovered = try CloudSyncMigration.resolve(
      plan, serverRecords: remote, existingZones: [rootID.zoneKey])
    #expect(recovered.pendingCount == 0)
    #expect(Set(recovered.entries.keys) == Set(remote.map { $0.id.key }))
    try CloudSyncMigration.verifyLocalCheckpoint(source, journal: recovered)
    var collision = try #require(remote.first { $0.entity == "Revision" })
    collision.id.name = "another-cloud-record-with-same-revision"
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.resolve(
        plan, serverRecords: remote + [collision], existingZones: [rootID.zoneKey])
    }
  }

  @Test func unmappedLocalInsertsQueueOnlyAfterCompleteServerComparison() throws {
    let (source, replica, root) = try fixtures.fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    _ = try fixtures.addRevision(
      source, root: root,
      value: .child(
        ChildProfile(familyID: try #require(root.value(forKey: "id") as? UUID), name: "Robin")))
    let preference = NSEntityDescription.insertNewObject(
      forEntityName: "PrivatePreference", into: source.context)
    source.context.assign(preference, to: try #require(source.privateStore))
    preference.setValue("bottle.fixture", forKey: "key")
    preference.setValue(Data("{}".utf8), forKey: "payload")
    preference.setValue(fixtures.date, forKey: "date")
    try source.context.save()
    try replica.reconcile()
    let rootEntry = try #require(
      replica.journal.entries.values.first { $0.baseline.entity == "FamilyRoot" })
    var remoteRoot = rootEntry.baseline
    remoteRoot.id.name = "legacy-root"
    remoteRoot = try fixtures.serverCopy(remoteRoot)
    let uri = root.objectID.uriRepresentation().absoluteString
    var plan = try CloudSyncMigration.capturePlan(
      source, account: "test-account", rootZones: [uri: remoteRoot.id])
    plan.localInsertURIs = Set(plan.journal.entries.values.map(\.objectURI))
    let recovered = try CloudSyncMigration.resolve(
      plan, serverRecords: [remoteRoot], existingZones: [remoteRoot.id.zoneKey])
    #expect(recovered.pendingCount == 2)
    #expect(recovered.newZones.count == 1)
    #expect(recovered.newZones.first?.zone == "Swaddle.PrivatePreferences")
    #expect(
      recovered.entries.values.first { $0.baseline.entity == "Revision" }?.pending?.familyRecordName
        == "legacy-root")
    try CloudSyncMigration.verifyLocalCheckpoint(source, journal: recovered)
    var changed = try #require(
      recovered.entries.values.first { $0.baseline.entity == "Revision" }?.baseline)
    changed.fields["tombstone"] = .integer(1)
    changed = try fixtures.serverCopy(changed)
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.resolve(
        plan, serverRecords: [remoteRoot, changed], existingZones: [remoteRoot.id.zoneKey])
    }
  }

  @Test func pendingInsertChangedDuringStoreCloseStillBlocksHandoff() throws {
    let (source, replica, root) = try fixtures.fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    try replica.reconcile()
    try fixtures.acknowledgeEverything(replica)
    let object = try fixtures.addRevision(
      source, root: root,
      value: .child(
        ChildProfile(familyID: try #require(root.value(forKey: "id") as? UUID), name: "Robin")))
    try replica.reconcile()
    let journal = replica.journal
    try CloudSyncMigration.verifyLocalCheckpoint(source, journal: journal)
    object.setValue(true, forKey: "tombstone")
    try source.context.save()
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.verifyLocalCheckpoint(source, journal: journal)
    }
  }

  @Test func physicalDeletionStillNeedsLegacyExportButInsertsDoNot() throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "SwaddleHistory-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = PersistenceController(directory: directory)
    if let error = persistence.loadError { throw error }
    let object = NSEntityDescription.insertNewObject(
      forEntityName: "PrivatePreference", into: persistence.context)
    persistence.context.assign(object, to: try #require(persistence.privateStore))
    object.setValue("fixture", forKey: "key")
    object.setValue(Data("{}".utf8), forKey: "payload")
    object.setValue(fixtures.date, forKey: "date")
    try persistence.context.save()
    try CloudSyncMigration.requireExportedDeletions(persistence)
    persistence.context.delete(object)
    try persistence.context.save()
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.requireExportedDeletions(persistence)
    }
  }
  @Test func diskHandoffVerifiesAfterClosingLegacyStoresAndPreservesIDs() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "SwaddleHandoffDisk-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let (source, replica, root) = try diskFixture(directory)
    let uri = root.objectID.uriRepresentation().absoluteString
    try replica.reconcile()
    try fixtures.acknowledgeEverything(replica)
    let expected = replica.journal
    let oldContainer = source.container
    try await source.adopt(.init(journal: expected)) { plan, reopened in
      #expect(reopened.container !== oldContainer)
      #expect(
        reopened.container.persistentStoreDescriptions.allSatisfy {
          $0.cloudKitContainerOptions == nil
        })
      #expect(reopened.controlledSync == nil && !reopened.usesCKSyncEngine)
      let prepared = try CareSyncJournal.read(from: directory.appending(path: "CareSync-v1.json"))
      #expect(prepared?.active == false)
      return plan.journal
    }
    let checkpoint = try #require(
      try CareSyncJournal.read(from: directory.appending(path: "CareSync-v1.json")))
    #expect(checkpoint.active && source.usesCKSyncEngine)
    #expect(checkpoint.entries.keys == expected.entries.keys)
    #expect(checkpoint.entries.values.first?.objectURI == uri)
    try CloudSyncMigration.verifyLocalCheckpoint(source, journal: checkpoint)
    #expect(
      FileManager.default.fileExists(
        atPath: directory.appending(path: "BeforeCKSyncEngine/Private.sqlite").path))
  }

  @Test func failedHandoffRestoresOneWriterAndRetainsChangesMadeDuringVerification() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "SwaddleHandoffRollback-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let (source, replica, _) = try diskFixture(directory)
    try replica.reconcile()
    try fixtures.acknowledgeEverything(replica)
    let plan = CloudSyncMigration.Plan(journal: replica.journal)
    await #expect(throws: CareSyncError.self) {
      try await source.adopt(plan) { plan, reopened in
        let root = try #require(
          try reopened.context.fetch(NSFetchRequest<NSManagedObject>(entityName: "FamilyRoot"))
            .first)
        root.setValue("Saved while checking", forKey: "name")
        try reopened.context.save()
        return plan.journal
      }
    }
    #expect(!source.usesCKSyncEngine && source.controlledSync == nil)
    #expect(source.loadError == nil)
    #expect(
      try CareSyncJournal.read(from: directory.appending(path: "CareSync-v1.json"))?.active == false
    )
    let root = try #require(
      try source.context.fetch(NSFetchRequest<NSManagedObject>(entityName: "FamilyRoot")).first)
    #expect(root.value(forKey: "name") as? String == "Saved while checking")
  }

  private func diskFixture(_ directory: URL) throws -> (
    PersistenceController, CareSyncReplica, NSManagedObject
  ) {
    let source = PersistenceController(directory: directory)
    if let error = source.loadError { throw error }
    let root = NSEntityDescription.insertNewObject(
      forEntityName: "FamilyRoot", into: source.context)
    source.context.assign(root, to: try #require(source.privateStore))
    root.setValue(UUID(), forKey: "id")
    root.setValue(UUID(), forKey: "ownerID")
    root.setValue("Our family", forKey: "name")
    root.setValue("America/New_York", forKey: "timeZone")
    try source.context.save()
    let replica = CareSyncReplica(
      persistence: source, journal: CareSyncJournal(account: "test-account"),
      url: directory.appending(path: "fixture.json"))
    return (source, replica, root)
  }

}
