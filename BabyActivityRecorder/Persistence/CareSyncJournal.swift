import CloudKit
import CoreData
import Foundation

nonisolated struct CareSyncJournal: Codable {
  struct Entry: Codable {
    var objectURI: String
    var baseline: CareCloudRecord
    var pending: CareCloudRecord?
    var deleting = false
    var blockedReason: String?
  }

  var version = 1
  var active = false
  var account: String
  var entries: [String: Entry] = [:]
  var engineStates: [CareCloudScope: Data] = [:]
  var shares: [String: Data] = [:]
  var incoming: [CareCloudRecord] = []
  var incomingDeletes: [CareCloudID] = []
  var removedZones: [CareCloudID] = []
  var newZones: [CareCloudID] = []
  var blockedZones: [String: String] = [:]
  var lastUpload: Date?
  var lastDownload: Date?
  var initialDownloadComplete = false
  var quarantined: [Entry] = []
  // Original, unshared copies retained after repairing a legacy cross-zone
  // relationship. Optional so journals written before recovery still decode.
  var retainedLegacyRecords: [CareCloudRecord]?

  var pendingCount: Int { entries.values.filter { $0.pending != nil || $0.deleting }.count }

  static func read(from url: URL) throws -> Self? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    do {
      let journal = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
      guard journal.version == 1 else { throw CareSyncError.corruptJournal }
      return journal
    } catch { throw CareSyncError.corruptJournal }
  }

  func write(to url: URL) throws {
    let data = try JSONEncoder().encode(self)
    try data.write(
      to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }
}

/// The journal contains both the durable outbox and a replayable inbox. A
/// received batch is written BEFORE Core Data changes; a crash between the two
/// saves replays the inbox without advancing past uncommitted care data.
@MainActor
final class CareSyncReplica {
  let persistence: PersistenceController
  let journalURL: URL
  private(set) var journal: CareSyncJournal
  private let writeJournal: (CareSyncJournal, URL) throws -> Void
  private var needsCheckpointReload = false

  init(
    persistence: PersistenceController, journal: CareSyncJournal, url: URL,
    writer: @escaping (CareSyncJournal, URL) throws -> Void = { try $0.write(to: $1) }
  ) {
    self.persistence = persistence
    self.journal = journal
    journalURL = url
    writeJournal = writer
  }

  func persist() throws {
    guard !needsCheckpointReload else { throw CareSyncError.unavailable }
    try writeJournal(journal, journalURL)
  }

  func activate() throws {
    journal.active = true
    try persist()
  }

  func saveEngineState(_ state: CKSyncEngine.State.Serialization, scope: CareCloudScope) throws {
    journal.engineStates[scope] = try JSONEncoder().encode(state)
    try persist()
  }

  func engineState(_ scope: CareCloudScope) throws -> CKSyncEngine.State.Serialization? {
    try journal.engineStates[scope].map {
      try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
    }
  }

  func recordID(for objectID: NSManagedObjectID) -> CKRecord.ID? {
    let uri = objectID.uriRepresentation().absoluteString
    return journal.entries.values.first { $0.objectURI == uri }?.baseline.id.recordID
  }

  func reference(for objectID: NSManagedObjectID) -> CareCloudID? {
    let uri = objectID.uriRepresentation().absoluteString
    return journal.entries.values.first { $0.objectURI == uri }?.baseline.id
  }

  func object(for uri: String) -> NSManagedObject? {
    guard let url = URL(string: uri),
      let id = persistence.container.persistentStoreCoordinator.managedObjectID(
        forURIRepresentation: url),
      let object = try? persistence.context.existingObject(with: id), !object.isDeleted
    else { return nil }
    return object
  }

  func allObjects() throws -> [NSManagedObject] {
    try ["FamilyRoot", "Revision", "PrivatePreference"].flatMap {
      try persistence.context.fetch(NSFetchRequest<NSManagedObject>(entityName: $0))
    }
  }

  /// Recompute from durable local rows, including after a crash between the
  /// local save and journaling. Acknowledgements never clear newer local work.
  func reconcile() throws {
    let objects = try allObjects()
    let byURI = Dictionary(
      uniqueKeysWithValues: objects.map { ($0.objectID.uriRepresentation().absoluteString, $0) })
    for (key, var entry) in journal.entries {
      guard let object = byURI[entry.objectURI] else {
        entry.deleting = true
        entry.pending = nil
        journal.entries[key] = entry
        continue
      }
      let parent =
        (object.entity.name == "Revision"
        ? object.value(forKey: "family") as? NSManagedObject : nil)
        .flatMap { reference(for: $0.objectID)?.name }
      let local = try CareCloudRecord(
        object: object, id: entry.baseline.id, familyRecordName: parent,
        systemFields: entry.baseline.systemFields)
      entry.pending =
        entry.baseline.systemFields != nil && local.fields == entry.baseline.fields ? nil : local
      entry.deleting = false
      journal.entries[key] = entry
    }
    var mapped = Set(journal.entries.values.map(\.objectURI))
    for object in objects where !mapped.contains(object.objectID.uriRepresentation().absoluteString)
    {
      let entity = object.entity.name ?? ""
      let scope: CareCloudScope =
        object.objectID.persistentStore == persistence.sharedStore ? .shared : .personal
      let zone: CKRecordZone.ID
      let parent: String?
      if entity == "Revision" {
        guard let family = object.value(forKey: "family") as? NSManagedObject,
          let familyID = reference(for: family.objectID)
        else { throw CareSyncError.invalidRecord }
        zone = familyID.zoneID
        parent = familyID.name
      } else {
        guard scope == .personal else { throw CareSyncError.invalidRecord }
        let name =
          entity == "FamilyRoot"
          ? "Swaddle.Family.\((object.value(forKey: "id") as? UUID)?.uuidString ?? "invalid")"
          : "Swaddle.PrivatePreferences"
        zone = CKRecordZone.ID(zoneName: name, ownerName: CKCurrentUserDefaultName)
        parent = nil
      }
      let logicalID =
        entity == "PrivatePreference"
        ? UUID().uuidString : (object.value(forKey: "id") as? UUID)?.uuidString
      guard let logicalID else { throw CareSyncError.invalidRecord }
      let id = CareCloudID(
        CKRecord.ID(recordName: "CD_\(entity)_\(logicalID)", zoneID: zone), scope: scope)
      let record = try CareCloudRecord(object: object, id: id, familyRecordName: parent)
      let uri = object.objectID.uriRepresentation().absoluteString
      journal.entries[id.key] = .init(objectURI: uri, baseline: record, pending: record)
      mapped.insert(uri)
      if scope == .personal, entity != "Revision",
        !journal.newZones.contains(where: { $0.zoneID == zone })
      {
        // saveZone is idempotent; shared zones are never created by a participant.
        journal.newZones.append(id)
      }
    }
    try persist()
  }

  func receive(_ records: [CareCloudRecord], deleted: [CareCloudID] = []) throws {
    for record in records { try record.validate() }
    for record in records {
      if let retained = journal.retainedLegacyRecords?.first(where: { $0.id == record.id }) {
        guard retained.fields == record.fields else { throw CareSyncError.revisionCollision }
        continue
      }
      journal.incoming.removeAll { $0.id == record.id }
      journal.incoming.append(record)
    }
    journal.incomingDeletes.append(contentsOf: deleted)
    try persist()
    try applyInbox()
  }

  func applyInbox() throws {
    if needsCheckpointReload {
      guard let recovered = try CareSyncJournal.read(from: journalURL) else {
        throw CareSyncError.corruptJournal
      }
      journal = recovered
      needsCheckpointReload = false
    }
    let checkpoint = journal
    let context = persistence.context
    do {
      for id in journal.incomingDeletes {
        if let entry = journal.entries.removeValue(forKey: id.key),
          let object = object(for: entry.objectURI)
        {
          if entry.pending != nil { journal.quarantined.append(entry) }
          if entry.baseline.entity == "FamilyRoot" {
            let children = journal.entries.filter {
              $0.value.baseline.id.scope == id.scope && $0.value.baseline.id.zoneID == id.zoneID
                && $0.value.baseline.familyRecordName == id.name
            }.map(\.key)
            for child in children {
              if let pending = journal.entries[child], pending.pending != nil {
                journal.quarantined.append(pending)
              }
              journal.entries.removeValue(forKey: child)
            }
          }
          context.delete(object)
        }
        journal.incoming.removeAll { $0.id == id }
        journal.shares.removeValue(forKey: id.key)
      }
      journal.incomingDeletes = []
      var remaining: [CareCloudRecord] = []
      for server in journal.incoming.sorted(by: {
        $0.entity == "FamilyRoot" && $1.entity != "FamilyRoot"
      }) {
        if journal.removedZones.contains(where: {
          $0.scope == server.id.scope && $0.zoneID == server.id.zoneID
        }) {
          continue
        }
        // A pending physical deletion must not be resurrected by a fetch.
        if journal.entries[server.id.key]?.deleting == true { continue }
        var parent: NSManagedObject?
        if server.entity == "Revision" {
          let rootID = CareCloudID(
            CKRecord.ID(recordName: server.familyRecordName ?? "", zoneID: server.id.zoneID),
            scope: server.id.scope)
          parent = journal.entries[rootID.key].flatMap { object(for: $0.objectURI) }
          if parent == nil {
            remaining.append(server)
            continue
          }
          guard case .bytes(let bytes) = server.fields["payload"],
            try JSONDecoder().decode(RecordEnvelope.self, from: bytes).value.familyID == parent?
              .value(forKey: "id") as? UUID
          else {
            throw CareSyncError.invalidRecord
          }
        }
        let existing = journal.entries[server.id.key]
        let target: NSManagedObject
        if let existing, let found = object(for: existing.objectURI) {
          target = found
        } else if let logicalID = server.logicalID {
          let request = NSFetchRequest<NSManagedObject>(entityName: server.entity)
          request.predicate = NSPredicate(
            format: "id == %@", UUID(uuidString: logicalID)! as NSUUID)
          request.affectedStores = [try store(server.id.scope)]
          let found = try context.fetch(request)
          guard found.count <= 1 else { throw CareSyncError.revisionCollision }
          if let found = found.first {
            if let mapped = reference(for: found.objectID), mapped != server.id {
              throw CareSyncError.revisionCollision
            }
            target = found
          } else {
            target = insert(server)
          }
        } else {
          target = insert(server)
        }
        var value = server
        if let existing, server.entity != "FamilyRoot" {
          guard existing.baseline.fields == server.fields else {
            throw CareSyncError.revisionCollision
          }
        }
        if let pending = existing?.pending {
          value = try CareCloudRecord.merge(
            local: pending, server: server, baseline: existing?.baseline)
        } else if existing == nil, !target.isInserted, server.entity == "Revision" {
          let local = try CareCloudRecord(
            object: target, id: server.id, familyRecordName: server.familyRecordName)
          guard local.fields == server.fields else { throw CareSyncError.revisionCollision }
        }
        try value.apply(to: target)
        if server.entity == "Revision" { target.setValue(parent, forKey: "family") }
        try context.obtainPermanentIDs(for: [target])
        journal.entries[server.id.key] = .init(
          objectURI: target.objectID.uriRepresentation().absoluteString,
          baseline: server, pending: value.fields == server.fields ? nil : value,
          blockedReason: existing?.blockedReason)
      }
      // Persist assigned object IDs before committing. In particular,
      // preferences have no UUID column, so this prevents duplicate rows
      // if the process stops after the SQLite commit but before our checkpoint.
      var staged = journal
      staged.incoming = checkpoint.incoming
      staged.incomingDeletes = checkpoint.incomingDeletes
      for id in checkpoint.incomingDeletes {
        if let entry = checkpoint.entries[id.key] { staged.entries[id.key] = entry }
      }
      try writeJournal(staged, journalURL)
      try context.save()
      journal.incoming = remaining
      try persist()
    } catch {
      context.rollback()
      journal = checkpoint
      // The persisted inbox survives even if the Core Data save completed
      // but the final journal write failed. Use its staged IDs even when the
      // user retries without restarting; otherwise preferences could duplicate.
      needsCheckpointReload = true
      if let recovered = try? CareSyncJournal.read(from: journalURL) {
        journal = recovered
        needsCheckpointReload = false
      }
      throw error
    }
  }

  private func insert(_ record: CareCloudRecord) -> NSManagedObject {
    let object = NSEntityDescription.insertNewObject(
      forEntityName: record.entity, into: persistence.context)
    if let store = record.id.scope == .personal ? persistence.privateStore : persistence.sharedStore
    {
      persistence.context.assign(object, to: store)
    }
    return object
  }

  func store(_ scope: CareCloudScope) throws -> NSPersistentStore {
    guard let store = scope == .personal ? persistence.privateStore : persistence.sharedStore else {
      throw CareSyncError.unavailable
    }
    return store
  }

  func acknowledge(_ records: [CareCloudRecord], deleted: [CareCloudID]) throws {
    for record in records {
      guard var entry = journal.entries[record.id.key] else { continue }
      entry.baseline = record
      entry.pending = nil
      entry.blockedReason = nil
      journal.entries[record.id.key] = entry
    }
    for id in deleted { journal.entries.removeValue(forKey: id.key) }
    if !records.isEmpty || !deleted.isEmpty { journal.lastUpload = .now }
    try reconcile()
  }

  func recordConflict(_ server: CareCloudRecord) throws { try receive([server]) }

  func block(_ id: CareCloudID, reason: String) throws {
    journal.entries[id.key]?.blockedReason = reason
    try persist()
  }

  func retryBlockedUploads() throws {
    for (key, entry) in journal.entries where entry.blockedReason != nil {
      let canRetry =
        entry.baseline.id.scope == .personal
        || object(for: entry.objectURI).map { canEdit($0.objectID) } == true
      if canRetry { journal.entries[key]?.blockedReason = nil }
    }
    journal.blockedZones = [:]
    try persist()
  }

  func blockZone(_ zone: CKRecordZone.ID, scope: CareCloudScope, reason: String) throws {
    let id = CareCloudID(zoneID: zone, scope: scope)
    journal.blockedZones[id.zoneKey] = reason
    try persist()
  }

  func removeZone(_ id: CareCloudID) throws {
    // Never recreate a revoked/deleted zone from retained pending writes.
    let keys = journal.entries.filter {
      $0.value.baseline.id.scope == id.scope && $0.value.baseline.id.zoneID == id.zoneID
    }.map(\.key)
    let ids = keys.compactMap { journal.entries[$0]?.baseline.id }
    journal.removedZones.append(id)
    journal.newZones.removeAll { $0.scope == id.scope && $0.zoneID == id.zoneID }
    journal.blockedZones.removeValue(forKey: id.zoneKey)
    try receive([], deleted: ids)
    for (key, data) in journal.shares {
      if let share = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKShare.self, from: data),
        share.recordID.zoneID == id.zoneID
      {
        journal.shares.removeValue(forKey: key)
      }
    }
    try persist()
  }

  func zoneSaved(_ zone: CKRecordZone.ID, scope: CareCloudScope) throws {
    journal.newZones.removeAll { $0.scope == scope && $0.zoneID == zone }
    journal.blockedZones.removeValue(
      forKey: CareCloudID(zoneID: zone, scope: scope).zoneKey)
    try persist()
  }

  func finishedDownload() throws {
    journal.lastDownload = .now
    journal.initialDownloadComplete = true
    try persist()
  }

  func allowAcceptedZone(_ zone: CKRecordZone.ID) throws {
    journal.removedZones.removeAll { $0.scope == .shared && $0.zoneID == zone }
    try persist()
  }

  func cacheShare(_ share: CKShare, scope: CareCloudScope) throws {
    journal.shares[CareCloudID(share.recordID, scope: scope).key] =
      try NSKeyedArchiver.archivedData(withRootObject: share, requiringSecureCoding: true)
    try persist()
  }

  func forgetShares(in zone: CKRecordZone.ID, scope: CareCloudScope) throws {
    for (key, bytes) in journal.shares {
      if let share = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKShare.self, from: bytes),
        share.recordID.zoneID == zone, CareCloudID(share.recordID, scope: scope).key == key
      {
        journal.shares.removeValue(forKey: key)
      }
    }
    try persist()
  }

  func share(for objectID: NSManagedObjectID) throws -> CKShare? {
    guard let id = reference(for: objectID) else { return nil }
    for (key, data) in journal.shares {
      let share = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKShare.self, from: data)
      if let share, share.recordID.zoneID == id.zoneID,
        CareCloudID(share.recordID, scope: id.scope).key == key
      {
        return share
      }
    }
    return nil
  }

  func canEdit(_ objectID: NSManagedObjectID) -> Bool {
    guard let id = reference(for: objectID) else {
      return objectID.persistentStore == persistence.privateStore
    }
    if id.scope == .personal { return true }
    guard let share = try? share(for: objectID), share.publicPermission == .none,
      let participant = share.currentUserParticipant, participant.acceptanceStatus == .accepted
    else { return false }
    return participant.permission == .readWrite
  }
}
