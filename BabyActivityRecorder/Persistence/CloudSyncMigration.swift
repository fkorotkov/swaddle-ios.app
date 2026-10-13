import CloudKit
import CoreData
import CryptoKit
import Foundation

@MainActor
enum CloudSyncMigration {
  struct Plan {
    var journal: CareSyncJournal
    var unmappedURIs: Set<String> = []
    var localInsertURIs: Set<String> = []
  }

  /// Only public Core Data/CloudKit APIs are used. We neither read nor edit
  /// Apple's private mirroring tables and never run two writers for a store.
  static func prepare(_ persistence: PersistenceController, account: String) async throws
    -> Plan
  {
    let cloud = CKContainer(identifier: PersistenceController.cloudContainer)
    guard CareCloudAccount.identity(try await cloud.userRecordID()) == account else {
      throw CareSyncError.accountChanged
    }
    persistence.migrationStage = String(localized: "Checking saved changes")
    let context = persistence.context
    guard !context.hasChanges else { throw CareSyncError.waitingForLegacy }
    // A failed exporter cannot complete an export barrier. Instead, verify
    // every live row against CloudKit and transfer proven missing inserts to
    // the new outbox. Physical deletions still require a completed export.
    try requireExportedDeletions(persistence)
    persistence.migrationStage = String(localized: "Verifying family access")
    let roots = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "FamilyRoot"))
    if roots.isEmpty, try !importsHaveCompleted(persistence) {
      throw CareSyncError.waitingForLegacy
    }
    var shares: [(CareCloudScope, CKShare)] = []
    var rootZones: [String: CareCloudID] = [:]
    for root in roots {
      let scope: CareCloudScope =
        root.objectID.persistentStore == persistence.sharedStore ? .shared : .personal
      guard let cached = try persistence.share(for: root.objectID) else {
        guard scope == .personal else { throw CareSyncError.waitingForLegacy }
        // Legacy unshared families live beside private defaults. Ask
        // Core Data to isolate the family before adopting its zone.
        // This creates no participant and sends no invitation.
        let created: CKShare = try await withCheckedThrowingContinuation { continuation in
          persistence.container.share([root], to: nil) { _, share, _, error in
            if let error {
              continuation.resume(throwing: error)
            } else if let share {
              continuation.resume(returning: share)
            } else {
              continuation.resume(throwing: CareSyncError.waitingForLegacy)
            }
          }
        }
        created.publicPermission = .none
        guard let store = persistence.privateStore else { throw CareSyncError.unavailable }
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, Error>) in
          persistence.container.persistUpdatedShare(created, in: store) { _, error in
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
          }
        }
        throw CareSyncError.waitingForLegacy
      }
      guard
        let share = try await scope.database(in: cloud).record(for: cached.recordID) as? CKShare,
        share.publicPermission == .none, share.url != nil
      else { throw CareSyncError.waitingForLegacy }
      if scope == .shared {
        _ = try CloudInvitationSnapshot(share: share, metadata: nil)
          .verifyingCurrentParticipant(account: account).acceptedIdentity(account: account)
      }
      shares.append((scope, share))
      rootZones[root.objectID.uriRepresentation().absoluteString] = CareCloudID(
        share.recordID, scope: scope)
    }
    persistence.migrationStage = String(localized: "Mapping saved records")
    var plan = try capturePlan(persistence, account: account, rootZones: rootZones)
    plan.localInsertURIs = try localInsertURIs(persistence)
    for (scope, share) in shares {
      let sharedDefaults = plan.journal.entries.values.contains {
        $0.baseline.entity == "PrivatePreference" && $0.baseline.id.scope == scope
          && $0.baseline.id.zoneID == share.recordID.zoneID
      }
      guard !sharedDefaults else {
        persistence.migrationStage = String(localized: "Private defaults mapped to a family share zone")
        throw CareSyncError.invalidRecord
      }
      plan.journal.shares[CareCloudID(share.recordID, scope: scope).key] =
        try NSKeyedArchiver.archivedData(withRootObject: share, requiringSecureCoding: true)
    }
    guard CareCloudAccount.identity(try await cloud.userRecordID()) == account else {
      throw CareSyncError.accountChanged
    }
    try requireExportedDeletions(persistence)
    return plan
  }

  /// Run only after the legacy stores have been closed and reopened WITHOUT
  /// mirroring. Otherwise an old export could race this scan and create a
  /// second CloudKit record for an object that had no public mapping yet.
  static func finish(_ plan: Plan, persistence: PersistenceController) async throws
    -> CareSyncJournal
  {
    let cloud = CKContainer(identifier: PersistenceController.cloudContainer)
    guard CareCloudAccount.identity(try await cloud.userRecordID()) == plan.journal.account else {
      throw CareSyncError.accountChanged
    }
    var records: [String: CareCloudRecord] = [:]
    var zones: Set<String> = []
    var unsharedPrivateZones: Set<String> = []
    for scope in CareCloudScope.allCases {
      let database = scope.database(in: cloud)
      for zone in try await database.allRecordZones() {
        guard zone.capabilities.contains(.fetchChanges) else { continue }
        let zoneKey = CareCloudID(zoneID: zone.zoneID, scope: scope).zoneKey
        zones.insert(zoneKey)
        if scope == .personal, zone.share == nil { unsharedPrivateZones.insert(zoneKey) }
        var token: CKServerChangeToken?
        var more = true
        while more {
          let page = try await database.recordZoneChanges(
            inZoneWith: zone.zoneID, since: token, resultsLimit: 200)
          for (_, result) in page.modificationResultsByID {
            let record = try result.get().record
            if record is CKShare { unsharedPrivateZones.remove(zoneKey) }
            // Shares and Apple's bookkeeping records are not care objects.
            guard
              ["CD_FamilyRoot", "CD_Revision", "CD_PrivatePreference"].contains(record.recordType)
            else { continue }
            let value: CareCloudRecord
            do { value = try CareCloudRecord(record, scope: scope) } catch {
              persistence.migrationStage =
                String(localized: "Unreadable server \(record.recordType) in \(scope.rawValue) database")
              throw error
            }
            records[value.id.key] = value
          }
          for deletion in page.deletions {
            records.removeValue(forKey: CareCloudID(deletion.recordID, scope: scope).key)
          }
          token = page.changeToken
          more = page.moreComing
          persistence.migrationStage = String(localized: "Verified \(records.count) iCloud records")
        }
      }
    }
    var journal = try resolve(
      plan, serverRecords: Array(records.values), existingZones: zones,
      unsharedPrivateZones: unsharedPrivateZones
    ) {
      persistence.migrationStage = $0
    }
    // Recheck access after the scan. A revoked/deleted share must never turn
    // missing records into a new family or resurrect a removed zone.
    for (key, data) in journal.shares {
      guard let cached = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKShare.self, from: data),
        let scope = CareCloudScope.allCases.first(where: {
          CareCloudID(cached.recordID, scope: $0).key == key
        }),
        let share = try await scope.database(in: cloud).record(for: cached.recordID) as? CKShare,
        share.publicPermission == .none, share.url != nil
      else { throw CareSyncError.revoked }
      if scope == .shared {
        _ = try CloudInvitationSnapshot(share: share, metadata: nil)
          .verifyingCurrentParticipant(account: journal.account).acceptedIdentity(
            account: journal.account)
      }
      journal.shares[key] = try NSKeyedArchiver.archivedData(
        withRootObject: share, requiringSecureCoding: true)
    }
    guard CareCloudAccount.identity(try await cloud.userRecordID()) == journal.account else {
      throw CareSyncError.accountChanged
    }
    persistence.migrationStage = String(localized: "Preserving \(journal.pendingCount) pending uploads")
    return journal
  }

  /// The input is an exhaustive, successfully paged server snapshot taken
  /// with the old writer stopped. No names, dates of care, or amounts are
  /// used to guess care identity: family/revision UUIDs must match exactly.
  static func resolve(
    _ plan: Plan, serverRecords: [CareCloudRecord], existingZones: Set<String>,
    unsharedPrivateZones: Set<String> = [],
    diagnose: (String) -> Void = { _ in }
  )
    throws -> CareSyncJournal
  {
    var journal = plan.journal
    journal.entries = [:]
    var roots: [String: CareCloudID] = [:]
    let ordered = plan.journal.entries.values.sorted {
      ($0.baseline.entity == "FamilyRoot" ? 0 : 1) < ($1.baseline.entity == "FamilyRoot" ? 0 : 1)
    }
    for original in ordered {
      var source = original
      let oldID = source.baseline.id
      var family: CareCloudRecord?
      if source.baseline.entity == "Revision" {
        guard let name = source.baseline.familyRecordName,
          let parent = roots[
            CareCloudID(CKRecord.ID(recordName: name, zoneID: oldID.zoneID), scope: oldID.scope).key
          ]
        else {
          diagnose("A revision's family cloud identity could not be resolved")
          throw CareSyncError.invalidRecord
        }
        source.baseline.fields["family"] = .string(parent.name)
        family = journal.entries[parent.key]?.baseline
      }
      let misplaced = serverRecords.filter {
        source.baseline.entity == "Revision" && $0.entity == "Revision"
          && $0.id.scope == oldID.scope && $0.id.zoneID != oldID.zoneID
          && $0.logicalID == source.baseline.logicalID
      }
      if !misplaced.isEmpty {
        guard misplaced.count == 1, let remote = misplaced.first, let family,
          oldID.scope == .personal, unsharedPrivateZones.contains(remote.id.zoneKey),
          journal.shares.values.contains(where: { data in
            guard
              let share = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKShare.self, from: data)
            else { return false }
            return share.recordID.zoneID == oldID.zoneID
          }),
          !serverRecords.contains(where: {
            $0.entity == "FamilyRoot" && $0.id.scope == remote.id.scope
              && $0.id.zoneID == remote.id.zoneID && $0.id.name == remote.familyRecordName
          }),
          remote.fields.filter({ $0.key != "family" })
            == source.baseline.fields.filter({ $0.key != "family" }),
          case .bytes(let payload) = remote.fields["payload"],
          try JSONDecoder().decode(RecordEnvelope.self, from: payload).value.familyID.uuidString
            == family.logicalID
        else {
          diagnose("A cross-zone revision could not be verified for the existing family share")
          throw CareSyncError.legacyRecordMismatch
        }
        // Never delete or modify the original. The existing family share gets
        // the verified immutable revision, with only its relationship repaired.
        journal.retainedLegacyRecords = (journal.retainedLegacyRecords ?? []) + misplaced
      }
      let matches = serverRecords.filter { remote in
        guard remote.entity == source.baseline.entity, remote.id.scope == oldID.scope else {
          return false
        }
        if remote.entity == "PrivatePreference" {
          return remote.fields["key"] == source.baseline.fields["key"]
            && remote.fields["date"] == source.baseline.fields["date"]
        }
        return remote.id.zoneID == oldID.zoneID && remote.logicalID == source.baseline.logicalID
      }
      guard matches.count <= 1 else {
        diagnose("Ambiguous \(source.baseline.entity) identity: \(matches.count) cloud matches")
        throw CareSyncError.legacyRecordMismatch
      }
      if let remote = matches.first {
        guard plan.unmappedURIs.contains(source.objectURI) || remote.id == oldID,
          remote.fields == source.baseline.fields, remote.systemFields != nil
        else {
          let fields = Set(remote.fields.keys).union(source.baseline.fields.keys).filter {
            remote.fields[$0] != source.baseline.fields[$0]
          }.sorted()
          var detail =
            String(localized: "Mismatch \(source.baseline.entity): \(fields.joined(separator: ", ")); cloud ID unchanged: \(String(describing: remote.id == oldID)); mapped: \(String(describing: !plan.unmappedURIs.contains(source.objectURI)))")
          if case .date(let server) = remote.fields["date"],
            case .date(let local) = source.baseline.fields["date"], server != local
          {
            detail += "; metadata date difference: \(abs(server - local)) seconds"
          }
          diagnose(detail)
          throw CareSyncError.legacyRecordMismatch
        }
        source.baseline = remote
        source.pending = nil
      } else {
        guard !serverRecords.contains(where: { $0.id == oldID }) else {
          diagnose("The destination cloud ID belongs to a different record")
          throw CareSyncError.legacyRecordMismatch
        }
        guard source.baseline.entity != "FamilyRoot",
          plan.localInsertURIs.contains(source.objectURI) || !misplaced.isEmpty
        else {
          diagnose(
            "No server \(source.baseline.entity) match; local insertion verified: \(plan.localInsertURIs.contains(source.objectURI))"
          )
          throw CareSyncError.legacyMappingUnavailable
        }
        if source.baseline.entity == "PrivatePreference",
          plan.unmappedURIs.contains(source.objectURI)
        {
          // Only brand-new private defaults may use the new private zone.
          // A family share zone is never created or replaced during recovery.
          if !existingZones.contains(oldID.zoneKey),
            !journal.newZones.contains(where: { $0.zoneKey == oldID.zoneKey })
          {
            journal.newZones.append(oldID)
          }
        } else if !existingZones.contains(oldID.zoneKey) {
          throw CareSyncError.revoked
        }
        source.baseline.systemFields = nil
        source.pending = source.baseline
      }
      if original.baseline.entity == "FamilyRoot" { roots[oldID.key] = source.baseline.id }
      guard journal.entries[source.baseline.id.key] == nil else {
        diagnose("Multiple local \(source.baseline.entity) rows resolve to one cloud record")
        throw CareSyncError.legacyRecordMismatch
      }
      journal.entries[source.baseline.id.key] = source
    }
    // Resolving an unmapped preference must not place it in a shared zone.
    for data in journal.shares.values {
      guard let share = try NSKeyedUnarchiver.unarchivedObject(ofClass: CKShare.self, from: data)
      else { throw CareSyncError.invalidRecord }
      guard
        !journal.entries.values.contains(where: {
          $0.baseline.entity == "PrivatePreference"
            && $0.baseline.id.zoneID == share.recordID.zoneID
        })
      else {
        diagnose("A private default was found inside a family share zone")
        throw CareSyncError.invalidRecord
      }
    }
    return journal
  }

  static func capture(_ persistence: PersistenceController) throws -> [String: CareSyncJournal
    .Entry]
  {
    try capturePlan(persistence, account: "", rootZones: nil).journal.entries
  }

  static func capturePlan(
    _ persistence: PersistenceController, account: String, rootZones: [String: CareCloudID]?
  ) throws -> Plan {
    var plan = Plan(journal: CareSyncJournal(account: account))
    var roots: [String: CareCloudID] = [:]
    for entity in ["FamilyRoot", "Revision", "PrivatePreference"] {
      persistence.migrationStage = String(localized: "Mapping \(entity) records")
      for object in try persistence.context.fetch(
        NSFetchRequest<NSManagedObject>(entityName: entity))
      {
        let uri = object.objectID.uriRepresentation().absoluteString
        let scope: CareCloudScope =
          object.objectID.persistentStore == persistence.sharedStore ? .shared : .personal
        let parent: String?
        let familyID: CareCloudID?
        if entity == "Revision" {
          guard let family = object.value(forKey: "family") as? NSManagedObject,
            let parentID = roots[family.objectID.uriRepresentation().absoluteString]
          else {
            throw CareSyncError.waitingForLegacy
          }
          parent = parentID.name
          familyID = parentID
        } else {
          parent = nil
          familyID = nil
        }
        var id: CareCloudID
        if let existing = persistence.container.recordID(for: object.objectID) {
          id = CareCloudID(existing, scope: scope)
        } else {
          guard let rootZones else { throw CareSyncError.legacyMappingUnavailable }
          let zone: CKRecordZone.ID
          if entity == "FamilyRoot", let root = rootZones[uri] {
            zone = root.zoneID
          } else if let familyID {
            zone = familyID.zoneID
          } else if entity == "PrivatePreference", scope == .personal {
            zone = CKRecordZone.ID(
              zoneName: "Swaddle.PrivatePreferences", ownerName: CKCurrentUserDefaultName)
          } else {
            throw CareSyncError.legacyMappingUnavailable
          }
          let logical =
            (object.value(forKey: entity == "PrivatePreference" ? "key" : "id") as? UUID)?
            .uuidString
            ?? SHA256.hash(data: Data(uri.utf8)).map { String(format: "%02x", $0) }.joined()
          id = CareCloudID(
            CKRecord.ID(recordName: "CD_\(entity)_\(logical)", zoneID: zone), scope: scope)
          plan.unmappedURIs.insert(uri)
        }
        if let familyID {
          guard familyID.scope == scope else {
            persistence.migrationStage = String(localized: "A revision and its family have different iCloud zones")
            throw CareSyncError.invalidRecord
          }
          if familyID.zoneID != id.zoneID {
            guard rootZones != nil, scope == .personal else {
              throw CareSyncError.legacyRecordMismatch
            }
            // Final server verification must prove this is an unshared orphan,
            // not a revision belonging to another family or shared zone.
            id = CareCloudID(
              CKRecord.ID(recordName: id.name, zoneID: familyID.zoneID), scope: scope)
            plan.unmappedURIs.insert(uri)
          }
        }
        if entity == "FamilyRoot" { roots[uri] = id }
        let record: CareCloudRecord
        do { record = try CareCloudRecord(object: object, id: id, familyRecordName: parent) } catch
        {
          persistence.migrationStage = String(localized: "Invalid local \(entity) fields")
          throw error
        }
        guard plan.journal.entries[record.id.key] == nil else {
          persistence.migrationStage = String(localized: "Duplicate local \(entity) cloud identity")
          throw CareSyncError.invalidRecord
        }
        plan.journal.entries[record.id.key] = .init(
          objectURI: object.objectID.uriRepresentation().absoluteString, baseline: record)
      }
    }
    return plan
  }

  private static func localInsertURIs(_ persistence: PersistenceController) throws -> Set<String> {
    let request = NSPersistentHistoryChangeRequest.fetchHistory(after: Date.distantPast)
    request.resultType = .transactionsAndChanges
    let transactions =
      try (persistence.context.execute(request) as? NSPersistentHistoryResult)?.result
      as? [NSPersistentHistoryTransaction] ?? []
    return Set(
      transactions.filter { $0.author == "LittleLog" }.flatMap { $0.changes ?? [] }
        .filter { $0.changeType == .insert }.map {
          $0.changedObjectID.uriRepresentation().absoluteString
        })
  }

  /// Recheck the closed/reopened stores before transferring ownership. Legacy
  /// mirroring can finish a download between the network check and store close;
  /// adopting that extra row without its cloud ID would upload a duplicate.
  static func verifyLocalCheckpoint(
    _ persistence: PersistenceController, journal: CareSyncJournal,
    requiresAcknowledgement: Bool = true
  ) throws {
    guard !persistence.context.hasChanges else { throw CareSyncError.waitingForLegacy }
    var byURI: [String: CareSyncJournal.Entry] = [:]
    for entry in journal.entries.values {
      let acknowledged = entry.baseline.systemFields != nil && entry.pending == nil
      let pendingInsert =
        entry.baseline.systemFields == nil
        && entry.pending == entry.baseline
        && ["Revision", "PrivatePreference"].contains(entry.baseline.entity)
      guard byURI[entry.objectURI] == nil,
        !requiresAcknowledgement || acknowledged || pendingInsert, !entry.deleting
      else { throw CareSyncError.waitingForLegacy }
      byURI[entry.objectURI] = entry
    }
    let objects = try ["FamilyRoot", "Revision", "PrivatePreference"].flatMap {
      try persistence.context.fetch(NSFetchRequest<NSManagedObject>(entityName: $0))
    }
    guard objects.count == byURI.count else { throw CareSyncError.waitingForLegacy }
    for object in objects {
      let uri = object.objectID.uriRepresentation().absoluteString
      let scope: CareCloudScope =
        object.objectID.persistentStore == persistence.sharedStore ? .shared : .personal
      guard let entry = byURI[uri], entry.baseline.id.scope == scope else {
        throw CareSyncError.waitingForLegacy
      }
      let parent: String?
      if object.entity.name == "Revision" {
        guard let family = object.value(forKey: "family") as? NSManagedObject,
          let parentID = byURI[family.objectID.uriRepresentation().absoluteString]?.baseline.id,
          parentID.scope == scope, parentID.zoneID == entry.baseline.id.zoneID
        else { throw CareSyncError.waitingForLegacy }
        parent = parentID.name
      } else {
        parent = nil
      }
      let local = try CareCloudRecord(
        object: object, id: entry.baseline.id, familyRecordName: parent,
        systemFields: entry.baseline.systemFields)
      guard local.entity == entry.baseline.entity, local.fields == entry.baseline.fields else {
        throw CareSyncError.waitingForLegacy
      }
    }
  }

  static func requireExportedDeletions(_ persistence: PersistenceController) throws {
    let historyRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: Date.distantPast)
    historyRequest.resultType = .transactionsAndChanges
    let history =
      try (persistence.context.execute(historyRequest) as? NSPersistentHistoryResult)?.result
      as? [NSPersistentHistoryTransaction] ?? []
    let request = NSPersistentCloudKitContainerEventRequest.fetchEvents(after: Date.distantPast)
    let events =
      try (persistence.context.execute(request) as? NSPersistentCloudKitContainerEventResult)?
      .result as? [NSPersistentCloudKitContainer.Event] ?? []
    // Only the private store permits physical app deletions (family removal
    // and Undo of private defaults). Shared care changes are append-only
    // revisions and are also checked record-by-record against the server.
    for store in [persistence.privateStore].compactMap({ $0 }) {
      let exportedThrough =
        events.filter {
          $0.storeIdentifier == store.identifier && $0.type == .export && $0.succeeded
            && $0.endDate != nil
        }.map(\.startDate).max() ?? .distantPast
      for transaction in history
      where transaction.storeID == store.identifier
        && transaction.author == "LittleLog" && transaction.timestamp > exportedThrough
      {
        guard let changes = transaction.changes else { throw CareSyncError.waitingForLegacy }
        if changes.contains(where: { $0.changeType == .delete }) {
          throw CareSyncError.legacyDeletionPending
        }
      }
    }
  }

  static func importsHaveCompleted(_ persistence: PersistenceController) throws -> Bool {
    let request = NSPersistentCloudKitContainerEventRequest.fetchEvents(after: Date.distantPast)
    let events =
      try (persistence.context.execute(request) as? NSPersistentCloudKitContainerEventResult)?
      .result as? [NSPersistentCloudKitContainer.Event] ?? []
    return persistence.container.persistentStoreCoordinator.persistentStores.allSatisfy { store in
      events.contains {
        $0.storeIdentifier == store.identifier && $0.type == .import && $0.succeeded
          && $0.endDate != nil
      }
    }
  }
}
