import CloudKit
import CoreData
import Foundation
import Testing

@testable import LittleLogCore

@MainActor
struct CareCloudSyncTests {
  let date = Date(timeIntervalSince1970: 1_790_000_000)

  func fixture(scope: CareCloudScope = .personal) throws -> (
    PersistenceController, CareSyncReplica, NSManagedObject
  ) {
    let persistence = PersistenceController(inMemory: true)
    if let error = persistence.loadError { throw error }
    let context = persistence.context
    let root = NSEntityDescription.insertNewObject(forEntityName: "FamilyRoot", into: context)
    context.assign(
      root, to: try #require(scope == .personal ? persistence.privateStore : persistence.sharedStore))
    root.setValue(UUID(), forKey: "id")
    root.setValue(UUID(), forKey: "ownerID")
    root.setValue("Our family", forKey: "name")
    root.setValue("America/New_York", forKey: "timeZone")
    try context.save()
    let url = FileManager.default.temporaryDirectory.appending(
      path: "SwaddleSyncTest-\(UUID()).json")
    let replica = CareSyncReplica(
      persistence: persistence, journal: CareSyncJournal(account: "test-account"), url: url)
    if scope == .shared {
      let id = CareCloudID(
        CKRecord.ID(recordName: "shared-family", zoneID: .init(
          zoneName: "shared-zone", ownerName: "other-icloud-owner")), scope: .shared)
      try replica.receive([serverCopy(CareCloudRecord(object: root, id: id, familyRecordName: nil))])
    }
    return (persistence, replica, root)
  }

  func serverCopy(_ record: CareCloudRecord) throws -> CareCloudRecord {
    try CareCloudRecord(record.record(), scope: record.id.scope)
  }

  func acknowledgeEverything(_ replica: CareSyncReplica) throws {
    let records = try replica.journal.entries.values.compactMap(\.pending).map(serverCopy)
    try replica.acknowledge(records, deleted: [])
  }

  func addRevision(
    _ persistence: PersistenceController, root: NSManagedObject, value: RecordValue,
    id: UUID = UUID(), parents: Set<UUID> = [], deleted: Bool = false
  ) throws -> NSManagedObject {
    let object = NSEntityDescription.insertNewObject(
      forEntityName: "Revision", into: persistence.context)
    persistence.context.assign(object, to: try #require(root.objectID.persistentStore))
    object.setValue(id, forKey: "id")
    object.setValue(value.id, forKey: "recordID")
    object.setValue(try JSONEncoder().encode(RecordEnvelope(value: value)), forKey: "payload")
    object.setValue(try JSONEncoder().encode(parents), forKey: "parentIDs")
    object.setValue(date, forKey: "date")
    object.setValue(root.value(forKey: "ownerID"), forKey: "editorID")
    object.setValue(deleted, forKey: "tombstone")
    object.setValue(root, forKey: "family")
    try persistence.context.save()
    return object
  }

  @Test func pendingWritesSurviveRepeatedReconciliationAndRestart() throws {
    let (persistence, replica, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    try replica.reconcile()
    let cloudID = try #require(replica.recordID(for: root.objectID))
    try replica.reconcile()
    #expect(replica.journal.pendingCount == 1)
    let reopened = CareSyncReplica(
      persistence: persistence,
      journal: try #require(try CareSyncJournal.read(from: replica.journalURL)),
      url: replica.journalURL)
    try reopened.reconcile()
    #expect(reopened.journal.pendingCount == 1)
    #expect(reopened.recordID(for: root.objectID) == cloudID)
    try acknowledgeEverything(reopened)
    #expect(reopened.journal.pendingCount == 0)
    root.setValue("Family update", forKey: "name")
    try persistence.context.save()  // Simulate a crash before journaling the save.
    let recovered = CareSyncReplica(
      persistence: persistence,
      journal: try #require(try CareSyncJournal.read(from: replica.journalURL)),
      url: replica.journalURL)
    try recovered.reconcile()
    #expect(recovered.journal.pendingCount == 1)
    #expect(recovered.recordID(for: root.objectID) == cloudID)
  }

  @Test func acknowledgementDoesNotDiscardAnEditMadeDuringUpload() throws {
    let (persistence, replica, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    try replica.reconcile()
    let sending = try replica.journal.entries.values.compactMap(\.pending).map(serverCopy)
    root.setValue("America/Chicago", forKey: "timeZone")
    try persistence.context.save()
    try replica.reconcile()
    try replica.acknowledge(sending, deleted: [])
    #expect(replica.journal.pendingCount == 1)
    #expect(
      replica.journal.entries.values.first?.pending?.fields["timeZone"]
        == .string("America/Chicago"))
    try acknowledgeEverything(replica)
    #expect(replica.journal.pendingCount == 0)
  }

  @Test func inPlaceBaselinePreservesLegacyRecordIdentityAndPayloadBytes() throws {
    let (persistence, replica, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    let zone = CKRecordZone.ID(
      zoneName: "com.apple.coredata.cloudkit.share.existing", ownerName: CKCurrentUserDefaultName)
    let id = CareCloudID(
      CKRecord.ID(recordName: "legacy-random-record-id", zoneID: zone), scope: .personal)
    let baseline = try serverCopy(CareCloudRecord(object: root, id: id, familyRecordName: nil))
    var journal = CareSyncJournal(account: "test-account")
    journal.entries[id.key] = .init(
      objectURI: root.objectID.uriRepresentation().absoluteString, baseline: baseline)
    let migrated = CareSyncReplica(
      persistence: persistence, journal: journal, url: replica.journalURL)
    try migrated.reconcile()
    #expect(migrated.journal.pendingCount == 0)
    #expect(migrated.recordID(for: root.objectID) == id.recordID)
    #expect(migrated.journal.newZones.isEmpty)
    let familyID = try #require(root.value(forKey: "id") as? UUID)
    let pump = PumpSession(
      familyID: familyID, motherID: UUID(), occurredAt: date, authorID: UUID(), totalML: 105,
      leftML: 60, rightML: 45, unit: .ml, note: "Preserve this note")
    let revision = try addRevision(persistence, root: root, value: .pumping(pump))
    try migrated.reconcile()
    let next = try #require(
      migrated.journal.entries.values.first { $0.baseline.entity == "Revision" }?.pending)
    #expect(next.id.zoneID == id.zoneID)
    #expect(next.familyRecordName == id.name)
    #expect(
      next.fields["payload"] == .bytes(try #require(revision.value(forKey: "payload") as? Data)))
    #expect(migrated.journal.newZones.isEmpty)
  }

  @Test func replayAndOutOfOrderArrivalDoNotDuplicateCareEntries() throws {
    let (source, sender, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: sender.journalURL) }
    let familyID = try #require(root.value(forKey: "id") as? UUID)
    let child = ChildProfile(familyID: familyID, name: "Robin")
    _ = try addRevision(source, root: root, value: .child(child))
    try sender.reconcile()
    let records = try sender.journal.entries.values.compactMap(\.pending).map(serverCopy)
    let receiver = PersistenceController(inMemory: true)
    let url = FileManager.default.temporaryDirectory.appending(
      path: "SwaddleReceiver-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let receiving = CareSyncReplica(
      persistence: receiver, journal: CareSyncJournal(account: "test-account"), url: url)
    try receiving.receive(records.filter { $0.entity == "Revision" })
    #expect(receiving.journal.incoming.count == 1)
    try receiving.receive(records.filter { $0.entity == "FamilyRoot" })
    #expect(receiving.journal.incoming.isEmpty)
    try receiving.receive(records)
    try receiving.reconcile()
    #expect(receiving.journal.pendingCount == 0)
    #expect(
      try receiver.context.count(
        for: NSFetchRequest<NSFetchRequestResult>(entityName: "FamilyRoot")) == 1)
    #expect(
      try receiver.context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Revision"))
        == 1)
  }

  @Test func bodyMeasurementsSyncWithOriginalUnitsPositionAndHistory() throws {
    let (source, sender, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: sender.journalURL) }
    let familyID = try #require(root.value(forKey: "id") as? UUID)
    let child = ChildProfile(familyID: familyID, name: "Robin")
    _ = try addRevision(source, root: root, value: .child(child))
    let length = Activity(familyID: familyID, childID: child.id, occurredAt: date,
      authorID: UUID(), note: "Clinic measurement",
      payload: .length(centimeters: 50.8, unit: .inch, position: .lyingDown))
    let head = Activity(familyID: familyID, childID: child.id, occurredAt: date,
      authorID: length.authorID, note: "Head circumference",
      payload: .headCircumference(centimeters: 35.56, unit: .inch))
    let initialID = UUID()
    _ = try addRevision(source, root: root, value: .activity(length), id: initialID)
    _ = try addRevision(source, root: root, value: .activity(head))
    var corrected = length
    corrected.payload = .length(centimeters: 51, unit: .cm, position: .standing)
    _ = try addRevision(source, root: root, value: .activity(corrected), parents: [initialID])
    try sender.reconcile()
    let records = try sender.journal.entries.values.compactMap(\.pending).map(serverCopy)
    let receiver = PersistenceController(inMemory: true)
    let url = FileManager.default.temporaryDirectory.appending(path: "SwaddleMeasurements-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let receiving = CareSyncReplica(persistence: receiver,
      journal: CareSyncJournal(account: "test-account"), url: url)
    try receiving.receive(records.filter { $0.entity == "Revision" }.reversed())
    try receiving.receive(records.filter { $0.entity == "FamilyRoot" })
    try receiving.receive(records)
    try receiving.reconcile()
    #expect(receiving.journal.pendingCount == 0)
    let revisions = try receiver.context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Revision"))
    #expect(revisions.count == 4)
    let envelopes = try revisions.map { object in
      try JSONDecoder().decode(RecordEnvelope.self, from: #require(object.value(forKey: "payload") as? Data))
    }
    for entry in [length, corrected, head] {
      let envelope = try #require(envelopes.first { $0.value == .activity(entry) })
      #expect(envelope.version == 5)
    }
    let edited = try #require(revisions.first { $0.value(forKey: "recordID") as? UUID == length.id
      && $0.value(forKey: "id") as? UUID != initialID })
    #expect(try JSONDecoder().decode(Set<UUID>.self,
      from: #require(edited.value(forKey: "parentIDs") as? Data)) == [initialID])
  }

  @Test func caregiverMergeSurvivesCloudReplayAndOutOfOrderProfileDelivery() throws {
    let (source, sender, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: sender.journalURL) }
    let familyID = try #require(root.value(forKey: "id") as? UUID)
    let ownerID = try #require(root.value(forKey: "ownerID") as? UUID)
    let kept = Caregiver(familyID: familyID, name: "Alex", isMother: true)
    var duplicate = Caregiver(familyID: familyID, name: "Alex old", isMother: true)
    let originalID = UUID()
    _ = try addRevision(source, root: root, value: .caregiver(duplicate), id: originalID)
    duplicate.mergedIntoID = kept.id
    let alias = try addRevision(
      source, root: root, value: .caregiver(duplicate),
      parents: [originalID], deleted: true)
    let keeper = try addRevision(source, root: root, value: .caregiver(kept))
    let pump = PumpSession(
      familyID: familyID, motherID: duplicate.id, occurredAt: date,
      authorID: ownerID, totalML: 105, unit: .ml, note: "Recorded offline")
    _ = try addRevision(source, root: root, value: .pumping(pump))
    try sender.reconcile()
    let records = try sender.journal.entries.values.compactMap(\.pending).map(serverCopy)
    let keeperID = try #require(sender.recordID(for: keeper.objectID))
    let aliasID = try #require(sender.recordID(for: alias.objectID))
    let cloudAlias = try #require(records.first { $0.id.recordID == aliasID })
    #expect(
      cloudAlias.fields["payload"] == .bytes(try #require(alias.value(forKey: "payload") as? Data)))

    let receiver = PersistenceController(inMemory: true)
    let url = FileManager.default.temporaryDirectory.appending(path: "SwaddleMerge-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let receiving = CareSyncReplica(
      persistence: receiver,
      journal: CareSyncJournal(account: "test-account"), url: url)
    func snapshot() throws -> FamilySnapshot {
      let objects = try receiver.context.fetch(
        NSFetchRequest<NSManagedObject>(entityName: "Revision"))
      let revisions = try objects.map { object -> RecordRevision in
        let envelope = try JSONDecoder().decode(
          RecordEnvelope.self,
          from: #require(object.value(forKey: "payload") as? Data))
        return RecordRevision(
          id: try #require(object.value(forKey: "id") as? UUID),
          recordID: envelope.value.id,
          parentIDs: try JSONDecoder().decode(
            Set<UUID>.self,
            from: #require(object.value(forKey: "parentIDs") as? Data)),
          value: envelope.value, date: date, editorID: ownerID,
          deleted: object.value(forKey: "tombstone") as? Bool ?? false)
      }
      return FamilySnapshot(
        family: Family(
          id: familyID, name: "Our family",
          timeZoneIdentifier: "America/New_York", ownerID: ownerID),
        records: RevisionProjection.project(revisions))
    }
    // The merge may arrive before its root or destination. Keep entries readable.
    try receiving.receive([cloudAlias])
    #expect(receiving.journal.incoming.count == 1)
    try receiving.receive(records.filter { $0.id.recordID != keeperID })
    #expect(try snapshot().pumps == [pump])
    try receiving.receive(records)
    try receiving.receive(records)
    try receiving.reconcile()
    let result = try snapshot()
    #expect(result.caregivers.map(\.id) == [kept.id])
    #expect(result.pumps.count == 1)
    #expect(result.pumps.first?.motherID == kept.id)
    #expect(result.pumps.first?.totalML == 105)
    #expect(result.record(pump.id)?.revision.value == .pumping(pump))
    #expect(
      try receiver.context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Revision"))
        == 4)
    #expect(receiving.journal.incoming.isEmpty)
    #expect(receiving.journal.pendingCount == 0)
  }

  @Test func privateDefaultsStayOutOfTheFamilyZone() throws {
    let (persistence, replica, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    let preference = NSEntityDescription.insertNewObject(
      forEntityName: "PrivatePreference", into: persistence.context)
    persistence.context.assign(preference, to: try #require(persistence.privateStore))
    preference.setValue("bottle.private", forKey: "key")
    preference.setValue(Data("private".utf8), forKey: "payload")
    preference.setValue(date, forKey: "date")
    try persistence.context.save()
    try replica.reconcile()
    let record = try #require(
      replica.journal.entries.values.first { $0.baseline.entity == "PrivatePreference" }?.pending)
    let family = try #require(
      replica.journal.entries.values.first { $0.baseline.entity == "FamilyRoot" })
    #expect(record.id.zoneID != family.baseline.id.zoneID)
    #expect(record.id.scope == .personal)
    var wrongScope = record
    wrongScope.id.scope = .shared
    #expect(throws: CareSyncError.self) { try wrongScope.validate() }
  }

  @Test func pendingDeletionCannotBeResurrectedByAnIncomingOldRecord() throws {
    let (persistence, replica, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    try replica.reconcile()
    try acknowledgeEverything(replica)
    let old = try #require(replica.journal.entries.values.first?.baseline)
    persistence.context.delete(root)
    try persistence.context.save()
    try replica.reconcile()
    try replica.receive([old])
    #expect(
      try persistence.context.count(
        for: NSFetchRequest<NSFetchRequestResult>(entityName: "FamilyRoot")) == 0)
    #expect(replica.journal.pendingCount == 1)
    try replica.acknowledge([], deleted: [old.id])
    #expect(replica.journal.pendingCount == 0)
  }

  @Test func zoneRemovalClearsVisibleRecordsAndPreservesUnsentWorkForRecovery() throws {
    let (persistence, replica, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    try replica.reconcile()
    let id = try #require(replica.journal.entries.values.first?.baseline.id)
    try replica.removeZone(id)
    try replica.reconcile()
    #expect(replica.journal.pendingCount == 0)
    #expect(replica.journal.newZones.isEmpty)
    #expect(replica.journal.quarantined.count == 1)
    #expect(
      try persistence.context.count(
        for: NSFetchRequest<NSFetchRequestResult>(entityName: "FamilyRoot")) == 0)
    #expect(root.isDeleted || root.managedObjectContext == nil)
  }

  @Test func immutableRevisionCollisionRetainsLocalValueAndInbox() throws {
    let (persistence, replica, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    let child = ChildProfile(
      familyID: try #require(root.value(forKey: "id") as? UUID), name: "Robin")
    _ = try addRevision(persistence, root: root, value: .child(child))
    try replica.reconcile()
    var conflicting = try #require(
      replica.journal.entries.values.first { $0.baseline.entity == "Revision" }?.pending)
    var changed = child
    changed.name = "Unexpected replacement"
    conflicting.fields["payload"] = .bytes(
      try JSONEncoder().encode(RecordEnvelope(value: .child(changed))))
    #expect(throws: CareSyncError.self) { try replica.receive([conflicting]) }
    #expect(replica.journal.incoming.count == 1)
    #expect(
      replica.journal.entries[conflicting.id.key]?.pending?.fields["payload"]
        != conflicting.fields["payload"])
  }

  @Test func familySettingsMergeKeepsIndependentEditsAndServerWinsSameField() throws {
    let (_, replica, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    try replica.reconcile()
    let base = try #require(replica.journal.entries.values.first?.baseline)
    var local = base
    var server = base
    local.fields["name"] = .string("Local name")
    server.fields["timeZone"] = .string("America/Chicago")
    let merged = try CareCloudRecord.merge(local: local, server: server, baseline: base)
    #expect(merged.fields["name"] == .string("Local name"))
    #expect(merged.fields["timeZone"] == .string("America/Chicago"))
    server.fields["name"] = .string("Server name")
    #expect(
      try CareCloudRecord.merge(local: local, server: server, baseline: base).fields["name"]
        == .string("Server name"))
    #expect(root.value(forKey: "name") as? String == "Our family")
  }

  @Test func schemaCodecReadsExternalizedPayloadAndRejectsUnsupportedVersions() throws {
    let (persistence, replica, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    let child = ChildProfile(
      familyID: try #require(root.value(forKey: "id") as? UUID), name: "Robin")
    _ = try addRevision(persistence, root: root, value: .child(child), deleted: true)
    try replica.reconcile()
    let encoded = try #require(
      replica.journal.entries.values.first { $0.baseline.entity == "Revision" }?.pending)
    let record = try encoded.record()
    let assetURL = FileManager.default.temporaryDirectory.appending(
      path: "SwaddlePayload-\(UUID())")
    defer { try? FileManager.default.removeItem(at: assetURL) }
    let payload = try #require(record["CD_payload"] as? Data)
    try payload.write(to: assetURL)
    record["CD_payload"] = Data() as NSData
    record["CD_payload_ckAsset"] = CKAsset(fileURL: assetURL)
    let decoded = try CareCloudRecord(record, scope: .personal)
    #expect(decoded.fields == encoded.fields)
    var envelope = RecordEnvelope(value: .child(child))
    envelope.version = 99
    record["CD_payload_ckAsset"] = nil
    record["CD_payload"] = try JSONEncoder().encode(envelope) as NSData
    #expect(throws: CareSyncError.self) { try CareCloudRecord(record, scope: .personal) }
  }

  @Test func unexportedLegacyRowsBlockMigrationWithoutChangingTheLog() throws {
    let (persistence, replica, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    #expect(throws: CareSyncError.self) { try CloudSyncMigration.capture(persistence) }
    #expect(
      try persistence.context.count(
        for: NSFetchRequest<NSFetchRequestResult>(entityName: "FamilyRoot")) == 1)
    #expect(!persistence.usesCKSyncEngine)
  }

  @Test func finalHandoffCheckRejectsChangesCommittedWhileLegacyStoresClose() throws {
    let (persistence, replica, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    let child = ChildProfile(
      familyID: try #require(root.value(forKey: "id") as? UUID), name: "Robin")
    let revision = try addRevision(persistence, root: root, value: .child(child))
    try replica.reconcile()
    try acknowledgeEverything(replica)
    let baseline = replica.journal
    try CloudSyncMigration.verifyLocalCheckpoint(persistence, journal: baseline)

    root.setValue("Changed during store close", forKey: "name")
    try persistence.context.save()
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.verifyLocalCheckpoint(persistence, journal: baseline)
    }
    root.setValue("Our family", forKey: "name")
    try persistence.context.save()
    try CloudSyncMigration.verifyLocalCheckpoint(persistence, journal: baseline)

    let added = try addRevision(persistence, root: root, value: .child(child))
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.verifyLocalCheckpoint(persistence, journal: baseline)
    }
    persistence.context.delete(added)
    try persistence.context.save()
    try CloudSyncMigration.verifyLocalCheckpoint(persistence, journal: baseline)

    persistence.context.delete(revision)
    try persistence.context.save()
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.verifyLocalCheckpoint(persistence, journal: baseline)
    }
    #expect(!persistence.usesCKSyncEngine)
  }

  @Test func finalHandoffCheckRequiresCorrectStoreAndFamilyMappings() throws {
    let (persistence, replica, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    _ = try addRevision(
      persistence, root: root,
      value: .child(
        ChildProfile(familyID: try #require(root.value(forKey: "id") as? UUID), name: "Robin")))
    try replica.reconcile()
    try acknowledgeEverything(replica)
    var journal = replica.journal
    let key = try #require(journal.entries.first { $0.value.baseline.entity == "Revision" }?.key)
    journal.entries[key]?.baseline.id.scope = .shared
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.verifyLocalCheckpoint(persistence, journal: journal)
    }
    journal = replica.journal
    journal.entries[key]?.baseline.fields["family"] = .string("wrong-family-record")
    #expect(throws: CareSyncError.self) {
      try CloudSyncMigration.verifyLocalCheckpoint(persistence, journal: journal)
    }
  }

  @Test func oneDatabaseFailureDoesNotPreventTheOtherFromFetching() async {
    var attempted: [CareCloudScope] = []
    let failures = await CareCloudSync.attemptBothDatabases { scope in
      attempted.append(scope)
      if scope == .personal { throw CKError(.networkUnavailable) }
    }
    #expect(Set(attempted) == Set(CareCloudScope.allCases))
    #expect(failures.count == 1)
    #expect((failures[.personal] as? CKError)?.code == .networkUnavailable)
  }

  @Test(arguments: [true, false])
  func crashAfterCoreDataCommitReplaysPreferencesWithoutDuplication(relaunch: Bool) throws {
    let persistence = PersistenceController(inMemory: true)
    let url = FileManager.default.temporaryDirectory.appending(path: "SwaddleCrash-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let id = CareCloudID(
      CKRecord.ID(
        recordName: "preference",
        zoneID: .init(zoneName: "preferences", ownerName: CKCurrentUserDefaultName)),
      scope: .personal)
    let record = try serverCopy(
      CareCloudRecord(
        id: id, entity: "PrivatePreference",
        fields: [
          "key": .string("bottle.private"), "payload": .bytes(Data("{}".utf8)),
          "date": .date(date.timeIntervalSince1970),
        ]))
    var writes = 0
    let replica = CareSyncReplica(
      persistence: persistence, journal: CareSyncJournal(account: "test-account"), url: url
    ) { journal, url in
      writes += 1
      if writes == 3 { throw CocoaError(.fileWriteOutOfSpace) }
      try journal.write(to: url)
    }
    #expect(throws: CocoaError.self) { try replica.receive([record]) }
    #expect(
      try persistence.context.count(
        for: NSFetchRequest<NSFetchRequestResult>(entityName: "PrivatePreference")) == 1)
    let restored =
      relaunch
      ? CareSyncReplica(
        persistence: persistence, journal: try #require(try CareSyncJournal.read(from: url)),
        url: url)
      : replica
    #expect(restored.journal.incoming.count == 1)
    try restored.applyInbox()
    try restored.reconcile()
    #expect(restored.journal.incoming.isEmpty)
    #expect(restored.journal.pendingCount == 0)
    #expect(
      try persistence.context.count(
        for: NSFetchRequest<NSFetchRequestResult>(entityName: "PrivatePreference")) == 1)
  }

  @Test func receivedRevisionCannotChangeAfterItWasAcknowledged() throws {
    let (persistence, replica, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    let child = ChildProfile(
      familyID: try #require(root.value(forKey: "id") as? UUID), name: "Robin")
    _ = try addRevision(persistence, root: root, value: .child(child))
    try replica.reconcile()
    try acknowledgeEverything(replica)
    var changed = try #require(
      replica.journal.entries.values.first { $0.baseline.entity == "Revision" }?.baseline)
    changed.fields["tombstone"] = .integer(1)
    #expect(throws: CareSyncError.self) { try replica.receive([changed]) }
    #expect(replica.journal.entries[changed.id.key]?.baseline.fields["tombstone"] == .integer(0))
  }

  @Test(arguments: [CKError.Code.permissionFailure, .invalidArguments])
  func permanentFailuresStayBlockedUntilAnExplicitRetry(code: CKError.Code) throws {
    let (_, replica, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    try replica.reconcile()
    let id = try #require(replica.journal.entries.values.first?.baseline.id)
    try CareCloudSync.handleFailedRecordUpload(CKError(code), id: id, replica: replica)
    try replica.reconcile()
    #expect(replica.journal.entries[id.key]?.blockedReason != nil)
    #expect(replica.journal.pendingCount == 1)
    try replica.retryBlockedUploads()
    #expect(replica.journal.entries[id.key]?.blockedReason == nil)
    #expect(CareCloudSync.isAutomaticallyRetried(CKError(.networkUnavailable)))
    #expect(!CareCloudSync.isAutomaticallyRetried(CKError(.permissionFailure)))
    #expect(!CareCloudSync.isAutomaticallyRetried(CKError(.invalidArguments)))
  }

  @Test(
    arguments: [CKError.Code.operationCancelled, .notAuthenticated, .accountTemporarilyUnavailable],
    CareCloudScope.allCases)
  func interruptedUploadsRemainRetryableAfterRestart(code: CKError.Code, scope: CareCloudScope) throws {
    let (persistence, replica, root) = try fixture(scope: scope)
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    try replica.reconcile()
    try acknowledgeEverything(replica)
    root.setValue("America/Chicago", forKey: "timeZone")
    try persistence.context.save()
    try replica.reconcile()
    let sending = try #require(replica.journal.entries.values.first?.pending)

    try CareCloudSync.handleFailedRecordUpload(CKError(code), id: sending.id, replica: replica)
    let restored = CareSyncReplica(
      persistence: persistence,
      journal: try #require(try CareSyncJournal.read(from: replica.journalURL)),
      url: replica.journalURL)
    try restored.reconcile()
    let retained = try #require(restored.journal.entries[sending.id.key])
    #expect(restored.journal.pendingCount == 1)
    #expect(retained.blockedReason == nil)
    #expect(retained.pending?.fields == sending.fields)
    #expect(retained.pending?.id == sending.id)
    // No manual unblock is needed, and a real acknowledgement drains the outbox.
    try restored.acknowledge([serverCopy(sending)], deleted: [])
    #expect(restored.journal.pendingCount == 0)
    #expect(restored.journal.entries.count == 1)
  }

  @Test(arguments: CareCloudScope.allCases)
  func cancelledDeletionRemainsQueuedAfterRestart(scope: CareCloudScope) throws {
    let (persistence, replica, root) = try fixture(scope: scope)
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    try replica.reconcile()
    try acknowledgeEverything(replica)
    let id = try #require(replica.reference(for: root.objectID))
    persistence.context.delete(root)
    try persistence.context.save()
    try replica.reconcile()
    try CareCloudSync.handleFailedRecordUpload(CKError(.operationCancelled), id: id, replica: replica)
    let restored = CareSyncReplica(
      persistence: persistence,
      journal: try #require(try CareSyncJournal.read(from: replica.journalURL)),
      url: replica.journalURL)
    try restored.reconcile()
    #expect(restored.journal.pendingCount == 1)
    #expect(restored.journal.entries[id.key]?.deleting == true)
    #expect(restored.journal.entries[id.key]?.blockedReason == nil)
    try restored.acknowledge([], deleted: [id])
    #expect(restored.journal.pendingCount == 0)
    #expect(restored.journal.entries.isEmpty)
  }

  @Test(arguments: [CKError.Code.operationCancelled, .notAuthenticated, .accountTemporarilyUnavailable])
  func interruptedZoneCreationKeepsRecordsRetryable(code: CKError.Code) throws {
    let (persistence, replica, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    try replica.reconcile()
    let zone = try #require(replica.journal.newZones.first)
    try CareCloudSync.handleFailedZoneUpload(
      CKError(code), zoneID: zone.zoneID, scope: zone.scope, replica: replica)
    let restored = CareSyncReplica(
      persistence: persistence,
      journal: try #require(try CareSyncJournal.read(from: replica.journalURL)),
      url: replica.journalURL)
    try restored.reconcile()
    #expect(restored.journal.blockedZones.isEmpty)
    #expect(restored.journal.newZones == [zone])
    #expect(restored.journal.pendingCount == 1)
    try restored.zoneSaved(zone.zoneID, scope: zone.scope)
    try acknowledgeEverything(restored)
    #expect(restored.journal.newZones.isEmpty)
    #expect(restored.journal.pendingCount == 0)
  }

  @Test func permanentZoneFailureSurvivesRestartWithoutDiscardingQueuedRecords() throws {
    let (persistence, replica, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: replica.journalURL) }
    try replica.reconcile()
    let id = try #require(replica.journal.newZones.first)
    let error = CKError(.permissionFailure)
    try CareCloudSync.handleFailedZoneUpload(
      error, zoneID: id.zoneID, scope: id.scope, replica: replica)
    let restored = CareSyncReplica(
      persistence: persistence,
      journal: try #require(try CareSyncJournal.read(from: replica.journalURL)),
      url: replica.journalURL)
    try restored.reconcile()
    #expect(restored.journal.blockedZones[id.zoneKey] == error.localizedDescription)
    #expect(restored.journal.pendingCount == 1)
    #expect(restored.journal.newZones.count == 1)
    try restored.retryBlockedUploads()
    #expect(restored.journal.blockedZones.isEmpty)
    #expect(restored.journal.pendingCount == 1)
  }

  @Test func sharedDownloadsUseTheSharedStoreAndRequireVerifiedWritePermission() throws {
    let (_, sender, _) = try fixture()
    defer { try? FileManager.default.removeItem(at: sender.journalURL) }
    try sender.reconcile()
    var record = try #require(sender.journal.entries.values.first?.pending)
    record.id.scope = .shared
    record.id.owner = "other-icloud-owner"
    let remote = try serverCopy(record)
    let receiver = PersistenceController(inMemory: true)
    let url = FileManager.default.temporaryDirectory.appending(path: "SwaddleShared-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let replica = CareSyncReplica(
      persistence: receiver, journal: CareSyncJournal(account: "recipient-account"), url: url)
    try replica.receive([remote])
    let root = try #require(
      try receiver.context.fetch(NSFetchRequest<NSManagedObject>(entityName: "FamilyRoot")).first)
    #expect(root.objectID.persistentStore == receiver.sharedStore)
    #expect(!replica.canEdit(root.objectID))
    #expect(replica.recordID(for: root.objectID) == remote.id.recordID)
    #expect(replica.journal.newZones.isEmpty)
  }

  @Test func recordsForDifferentFamiliesCannotBeLinkedByMistake() throws {
    let (persistence, sender, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: sender.journalURL) }
    _ = try addRevision(
      persistence, root: root, value: .child(ChildProfile(familyID: UUID(), name: "Wrong family")))
    try sender.reconcile()
    let records = try sender.journal.entries.values.compactMap(\.pending).map(serverCopy)
    let receiver = PersistenceController(inMemory: true)
    let url = FileManager.default.temporaryDirectory.appending(
      path: "SwaddleFamilyMismatch-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let replica = CareSyncReplica(
      persistence: receiver, journal: CareSyncJournal(account: "test-account"), url: url)
    #expect(throws: CareSyncError.self) { try replica.receive(records) }
    #expect(
      try receiver.context.count(
        for: NSFetchRequest<NSFetchRequestResult>(entityName: "FamilyRoot")) == 0)
    #expect(
      try receiver.context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Revision"))
        == 0)
  }

  @Test func twoReplicasRetainConcurrentRevisionHeads() throws {
    let (first, firstSync, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: firstSync.journalURL) }
    let familyID = try #require(root.value(forKey: "id") as? UUID)
    let child = ChildProfile(familyID: familyID, name: "Robin")
    let originalID = UUID()
    _ = try addRevision(first, root: root, value: .child(child), id: originalID)
    try firstSync.reconcile()
    let original = try firstSync.journal.entries.values.compactMap(\.pending).map(serverCopy)
    try firstSync.acknowledge(original, deleted: [])
    let second = PersistenceController(inMemory: true)
    let url = FileManager.default.temporaryDirectory.appending(path: "SwaddleSecond-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let secondSync = CareSyncReplica(
      persistence: second, journal: CareSyncJournal(account: "test-account"), url: url)
    try secondSync.receive(original)
    let secondRoot = try #require(
      try second.context.fetch(NSFetchRequest<NSManagedObject>(entityName: "FamilyRoot")).first)
    var firstEdit = child
    var secondEdit = child
    firstEdit.name = "First edit"
    secondEdit.name = "Second edit"
    _ = try addRevision(first, root: root, value: .child(firstEdit), parents: [originalID])
    _ = try addRevision(second, root: secondRoot, value: .child(secondEdit), parents: [originalID])
    try firstSync.reconcile()
    try secondSync.reconcile()
    let fromFirst = try firstSync.journal.entries.values.compactMap(\.pending).map(serverCopy)
    let fromSecond = try secondSync.journal.entries.values.compactMap(\.pending).map(serverCopy)
    try firstSync.receive(fromSecond)
    try secondSync.receive(fromFirst)
    try firstSync.acknowledge(fromFirst, deleted: [])
    try secondSync.acknowledge(fromSecond, deleted: [])
    for replica in [firstSync, secondSync] {
      let revisions = try replica.journal.entries.values.filter { $0.baseline.entity == "Revision" }
        .map { entry -> RecordRevision in
          let record = entry.baseline
          guard case .bytes(let payload) = record.fields["payload"],
            case .bytes(let parents) = record.fields["parentIDs"],
            case .string(let id) = record.fields["id"],
            case .string(let editor) = record.fields["editorID"]
          else {
            throw CareSyncError.invalidRecord
          }
          return RecordRevision(
            id: UUID(uuidString: id)!, recordID: child.id,
            parentIDs: try JSONDecoder().decode(Set<UUID>.self, from: parents),
            value: try JSONDecoder().decode(RecordEnvelope.self, from: payload).value,
            date: date, editorID: UUID(uuidString: editor)!, deleted: false)
        }
      let projected = try #require(RevisionProjection.project(revisions).first)
      #expect(projected.hasConflict)
      #expect(projected.heads.count == 2)
      #expect(revisions.count == 3)
      #expect(replica.journal.pendingCount == 0)
    }
  }

  @Test func milestonePayloadReplaysThroughCloudKitWithoutSchemaChanges() throws {
    let (source, sender, root) = try fixture()
    defer { try? FileManager.default.removeItem(at: sender.journalURL) }
    let familyID = try #require(root.value(forKey: "id") as? UUID)
    let author = try #require(root.value(forKey: "ownerID") as? UUID)
    let child = ChildProfile(familyID: familyID, name: "Robin")
    let skill = MilestoneCatalog.motorSkills[0]
    let observed = MilestoneObservation(familyID: familyID, childID: child.id,
      skillID: skill.id, sourceVersion: skill.sourceVersion, skillTitle: skill.title,
      status: .seen, firstNoticedAt: date, note: "Sitting together", authorID: author, recordedAt: date)
    _ = try addRevision(source, root: root, value: .child(child))
    _ = try addRevision(source, root: root, value: .milestone(observed))
    try sender.reconcile()
    let records = try sender.journal.entries.values.compactMap(\.pending).map(serverCopy)
    let receiver = PersistenceController(inMemory: true)
    let url = FileManager.default.temporaryDirectory.appending(path: "SwaddleMilestone-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let receiving = CareSyncReplica(persistence: receiver, journal: CareSyncJournal(account: "test-account"), url: url)
    try receiving.receive(records)
    try receiving.receive(records)
    try receiving.reconcile()
    let values = try receiver.context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Revision")).map {
      try JSONDecoder().decode(RecordEnvelope.self, from: #require($0.value(forKey: "payload") as? Data)).value
    }
    #expect(values.count == 2)
    #expect(values.contains(.milestone(observed)))
    #expect(receiving.journal.incoming.isEmpty && receiving.journal.pendingCount == 0)
  }

  @Test func unreadableCheckpointFailsClosed() throws {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "SwaddleBadJournal-\(UUID()).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("broken".utf8).write(to: url)
    #expect(throws: CareSyncError.self) { try CareSyncJournal.read(from: url) }
    var journal = CareSyncJournal(account: "original-account")
    journal.version = 99
    try journal.write(to: url)
    #expect(throws: CareSyncError.self) { try CareSyncJournal.read(from: url) }
  }
}
