import CloudKit
import CoreData
import Foundation

extension Notification.Name {
  static let careSyncChanged = Notification.Name("Swaddle.careSyncChanged")
}

@MainActor
final class CareCloudSync: CKSyncEngineDelegate {
  let replica: CareSyncReplica
  private let cloud = CKContainer(identifier: PersistenceController.cloudContainer)
  private var engines: [CareCloudScope: CKSyncEngine] = [:]
  private var operation: Task<Void, Error>?
  private var saveTask: Task<Void, Never>?
  private var suspended = false
  private var needsAnotherPass = false
  private var fetchFailures = Set<CareCloudScope>()
  private(set) var isSyncing = false
  private(set) var message = String(localized: "Ready to sync")
  private(set) var failure: Error?

  init(replica: CareSyncReplica) { self.replica = replica }

  func start() async throws {
    try await verifyAccount()
    guard engines.isEmpty else { return }
    try replica.applyInbox()
    try replica.reconcile()
    suspended = false
    for scope in CareCloudScope.allCases {
      var configuration = CKSyncEngine.Configuration(
        database: scope.database(in: cloud),
        stateSerialization: try replica.engineState(scope), delegate: self)
      configuration.subscriptionID = "Swaddle.CKSyncEngine.\(scope.rawValue).v1"
      engines[scope] = CKSyncEngine(configuration)
    }
    queuePendingChanges()
  }

  func localSaveCompleted() {
    do {
      try replica.reconcile()
      queuePendingChanges()
      publish("Saved on this iPhone · Upload pending")
    } catch {
      stopForStorageError(error)
      return
    }
    needsAnotherPass = true
    saveTask?.cancel()
    saveTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      try? await self?.sync()
    }
  }

  func sync() async throws {
    if let operation { return try await operation.value }
    let task = Task { @MainActor in
      defer {
        self.isSyncing = false
        self.operation = nil
        self.notify()
      }
      self.isSyncing = true
      self.failure = nil
      do {
        try await self.start()
        guard !self.suspended else { throw CareSyncError.accountChanged }
        // A revoked invitation can make this lookup fail. Still fetch database
        // changes so the engine can discover the removed zone and clear it.
        var sharesVerified = false
        do {
          try await self.refreshShares()
          sharesVerified = true
          try self.replica.retryBlockedUploads()
        } catch {
          try Task.checkCancellation()
          guard !self.suspended else { throw error }
        }
        repeat {
          self.needsAnotherPass = false
          try Task.checkCancellation()
          try await self.verifyAccount()
          try self.replica.reconcile()
          self.queuePendingChanges()
          self.publish("Uploading saved entries…")
          let sendErrors = await Self.attemptBothDatabases { scope in
            guard !self.suspended, let engine = self.engines[scope] else {
              throw CareSyncError.unavailable
            }
            if scope == .shared && !sharesVerified { return }
            try await engine.sendChanges()
          }
          if let error = sendErrors.values.first { self.failure = error }
          self.publish("Checking for family updates…")
          self.fetchFailures = []
          let fetchErrors = await Self.attemptBothDatabases { scope in
            guard !self.suspended, let engine = self.engines[scope] else {
              throw CareSyncError.unavailable
            }
            try await engine.fetchChanges()
          }
          self.fetchFailures.formUnion(fetchErrors.keys)
          if let error = fetchErrors.values.first { self.failure = error }
          try await self.verifyAccount()
          try await self.refreshShares()
          if !sharesVerified {
            sharesVerified = true
            try self.replica.retryBlockedUploads()
            self.needsAnotherPass = true
          }
          guard self.fetchFailures.isEmpty, self.replica.journal.incoming.isEmpty else {
            throw self.failure ?? CareSyncError.unavailable
          }
          if let failure = self.failure { throw failure }
          try self.replica.finishedDownload()
        } while self.needsAnotherPass
        self.publish(
          self.replica.journal.pendingCount == 0
            ? "Up to date with iCloud" : "Saved on this iPhone · Upload pending")
      } catch {
        self.failure = error
        self.publish(error.localizedDescription)
        throw error
      }
    }
    operation = task
    try await task.value
  }

  func verifyAccount() async throws {
    let identity = CareCloudAccount.identity(try await cloud.userRecordID())
    guard identity == replica.journal.account else {
      suspend()
      throw CareSyncError.accountChanged
    }
  }

  func suspend() {
    suspended = true
    saveTask?.cancel()
    operation?.cancel()
    let previous = Array(engines.values)
    engines = [:]
    Task { for engine in previous { await engine.cancelOperations() } }
  }

  private func publish(_ message: String) {
    self.message = message
    notify()
  }
  private func notify() {
    NotificationCenter.default.post(name: .careSyncChanged, object: replica.persistence)
  }

  private func stopForStorageError(_ error: Error) {
    failure = error
    suspend()
    publish(error.localizedDescription)
  }

  private func queuePendingChanges() {
    guard !suspended else { return }
    for (scope, engine) in engines {
      let desired = Set(
        replica.journal.entries.values.compactMap {
          entry -> CKSyncEngine.PendingRecordZoneChange? in
          guard entry.baseline.id.scope == scope, entry.blockedReason == nil,
            replica.journal.blockedZones[entry.baseline.id.zoneKey] == nil
          else { return nil }
          if entry.deleting { return .deleteRecord(entry.baseline.id.recordID) }
          if entry.pending != nil { return .saveRecord(entry.baseline.id.recordID) }
          return nil
        })
      let current = Set(engine.state.pendingRecordZoneChanges)
      engine.state.remove(pendingRecordZoneChanges: Array(current.subtracting(desired)))
      engine.state.add(pendingRecordZoneChanges: Array(desired.subtracting(current)))
      let zones = Set(
        replica.journal.newZones.filter {
          $0.scope == scope && replica.journal.blockedZones[$0.zoneKey] == nil
        }.map {
          CKSyncEngine.PendingDatabaseChange.saveZone(CKRecordZone(zoneID: $0.zoneID))
        })
      let pending = Set(engine.state.pendingDatabaseChanges)
      engine.state.remove(pendingDatabaseChanges: Array(pending.subtracting(zones)))
      engine.state.add(pendingDatabaseChanges: Array(zones.subtracting(pending)))
    }
  }

  func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    guard !suspended, let scope = scope(for: syncEngine) else { return nil }
    do {
      // Construct a bounded batch from the journal. New edits stay queued
      // while this snapshot is in flight and are checked again on acknowledgement.
      let pending = syncEngine.state.pendingRecordZoneChanges.filter {
        context.options.scope.contains($0)
      }.prefix(200)
      var records: [CKRecord] = []
      var deleted: [CKRecord.ID] = []
      for change in pending {
        switch change {
        case .saveRecord(let id):
          if let value = replica.journal.entries[CareCloudID(id, scope: scope).key]?.pending {
            records.append(try value.record())
          }
        case .deleteRecord(let id): deleted.append(id)
        @unknown default: break
        }
      }
      guard !records.isEmpty || !deleted.isEmpty else { return nil }
      return .init(recordsToSave: records, recordIDsToDelete: deleted)
    } catch {
      stopForStorageError(error)
      return nil
    }
  }

  func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    guard !suspended, let scope = scope(for: syncEngine) else { return }
    do {
      switch event {
      case .stateUpdate(let event):
        try replica.saveEngineState(event.stateSerialization, scope: scope)
      case .accountChange(let event):
        switch event.changeType {
        case .signIn(let currentUser):
          guard CareCloudAccount.identity(currentUser) == replica.journal.account else {
            throw CareSyncError.accountChanged
          }
        case .signOut, .switchAccounts: throw CareSyncError.accountChanged
        @unknown default: throw CareSyncError.accountChanged
        }
      case .fetchedRecordZoneChanges(let event):
        var records: [CareCloudRecord] = []
        for modification in event.modifications {
          if let share = modification.record as? CKShare {
            try replica.cacheShare(share, scope: scope)
          } else if CareCloudRecord.attributes[
            modification.record["CD_entityName"] as? String ?? ""] != nil
          {
            records.append(try CareCloudRecord(modification.record, scope: scope))
          }
        }
        try replica.receive(
          records, deleted: event.deletions.map { CareCloudID($0.recordID, scope: scope) })
        queuePendingChanges()
        notify()
      case .fetchedDatabaseChanges(let event):
        for deletion in event.deletions {
          try replica.removeZone(CareCloudID(zoneID: deletion.zoneID, scope: scope))
        }
        queuePendingChanges()
        notify()
      case .sentRecordZoneChanges(let event):
        try replica.acknowledge(
          try event.savedRecords.map { try CareCloudRecord($0, scope: scope) },
          deleted: event.deletedRecordIDs.map { CareCloudID($0, scope: scope) })
        for failed in event.failedRecordSaves {
          if failed.error.code == .serverRecordChanged, let server = failed.error.serverRecord {
            try replica.recordConflict(CareCloudRecord(server, scope: scope))
          } else if failed.error.code == .zoneNotFound,
            !replica.journal.newZones.contains(where: {
              $0.scope == scope && $0.zoneID == failed.record.recordID.zoneID
            })
          {
            // A missing established zone is a deletion/revocation, not
            // permission to recreate a family's old data.
            try replica.removeZone(CareCloudID(failed.record.recordID, scope: scope))
            failure = CareSyncError.revoked
          } else {
            failure = failed.error
            try Self.handleFailedRecordUpload(
              failed.error, id: CareCloudID(failed.record.recordID, scope: scope), replica: replica)
          }
        }
        for (id, error) in event.failedRecordDeletes {
          if error.code == .unknownItem {
            try replica.acknowledge([], deleted: [CareCloudID(id, scope: scope)])
          } else {
            failure = error
            try Self.handleFailedRecordUpload(
              error, id: CareCloudID(id, scope: scope), replica: replica)
          }
        }
        queuePendingChanges()
        notify()
      case .sentDatabaseChanges(let event):
        for zone in event.savedZones { try replica.zoneSaved(zone.zoneID, scope: scope) }
        for failed in event.failedZoneSaves {
          failure = failed.error
          try Self.handleFailedZoneUpload(
            failed.error, zoneID: failed.zone.zoneID, scope: scope, replica: replica)
        }
        queuePendingChanges()
      case .willFetchChanges:
        fetchFailures.remove(scope)
        if !isSyncing { publish("Checking for family updates…") }
      case .didFetchRecordZoneChanges(let event):
        if let error = event.error {
          fetchFailures.insert(scope)
          failure = error
          publish(error.localizedDescription)
        }
      case .didFetchChanges:
        // This event has no top-level error. Only successful awaited fetches
        // update the public checkpoint and unlock first-run family discovery.
        if !isSyncing {
          publish(failure?.localizedDescription ?? "Automatic iCloud check finished")
        }
        notify()
      case .willSendChanges: if !isSyncing { publish("Uploading saved entries…") }
      case .didSendChanges:
        if !isSyncing {
          publish(
            failure?.localizedDescription
              ?? (replica.journal.pendingCount == 0 ? "Saved to iCloud" : "Upload pending"))
        }
      default: break
      }
    } catch { stopForStorageError(error) }
  }

  private func scope(for engine: CKSyncEngine) -> CareCloudScope? {
    engines.first { $0.value === engine }?.key
  }

  /// A failure in one database must not hide updates or revocations in the other.
  static func attemptBothDatabases(
    _ operation: (CareCloudScope) async throws -> Void
  ) async -> [CareCloudScope: Error] {
    var failures: [CareCloudScope: Error] = [:]
    for scope in CareCloudScope.allCases {
      do { try await operation(scope) } catch { failures[scope] = error }
    }
    return failures
  }

  nonisolated static func isAutomaticallyRetried(_ error: CKError) -> Bool {
    // CKSyncEngine retains and retries these changes. Blocking them here would
    // remove them from its pending state in queuePendingChanges(), preventing
    // recovery after an interrupted operation or temporary account outage.
    [
      .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited,
      .zoneBusy, .batchRequestFailed, .operationCancelled, .notAuthenticated,
      .accountTemporarilyUnavailable,
    ].contains(error.code)
  }

  static func handleFailedRecordUpload(
    _ error: CKError, id: CareCloudID, replica: CareSyncReplica
  ) throws {
    guard !isAutomaticallyRetried(error) else { return }
    try replica.block(id, reason: error.localizedDescription)
  }

  static func handleFailedZoneUpload(
    _ error: CKError, zoneID: CKRecordZone.ID, scope: CareCloudScope, replica: CareSyncReplica
  ) throws {
    guard !isAutomaticallyRetried(error) else { return }
    try replica.blockZone(zoneID, scope: scope, reason: error.localizedDescription)
  }

  func refreshShares() async throws {
    let roots = replica.journal.entries.values.filter {
      $0.baseline.entity == "FamilyRoot" && !$0.deleting
    }
    for entry in roots {
      let id = entry.baseline.id
      guard let object = replica.object(for: entry.objectURI) else { continue }
      let cached = try replica.share(for: object.objectID)
      let shareID =
        cached?.recordID ?? CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: id.zoneID)
      do {
        guard let share = try await id.scope.database(in: cloud).record(for: shareID) as? CKShare
        else { throw CareSyncError.invalidRecord }
        try await verifyAccount()
        try replica.cacheShare(share, scope: id.scope)
        if id.scope == .shared {
          _ = try CloudInvitationSnapshot(share: share, metadata: nil)
            .verifyingCurrentParticipant(account: replica.journal.account).acceptedIdentity(
              account: replica.journal.account)
        }
      } catch let error as CKError where error.code == .unknownItem && id.scope == .personal {
        // A new family hasn't created its private invitation yet.
        try replica.forgetShares(in: id.zoneID, scope: id.scope)
      }
    }
    notify()
  }

  func prepareShare(for objectID: NSManagedObjectID) async throws -> CKShare {
    try await sync()
    guard let id = replica.reference(for: objectID) else { throw CareSyncError.unavailable }
    if let share = try replica.share(for: objectID), share.url != nil { return share }
    let isolatedFamilyZone =
      id.zone.hasPrefix("Swaddle.Family.")
      || id.zone.hasPrefix("com.apple.coredata.cloudkit.share.")
    guard id.scope == .personal, isolatedFamilyZone,
      replica.journal.pendingCount == 0
    else {
      throw CareSyncError.waitingForLegacy
    }
    let share = CKShare(recordZoneID: id.zoneID)
    share.publicPermission = .none
    share[CKShare.SystemFieldKey.title] = "Swaddle · Our family" as NSString
    return try await saveShare(share)
  }

  func saveShare(_ share: CKShare) async throws -> CKShare {
    try await verifyAccount()
    guard share.publicPermission == .none else { throw CloudInvitationError.unsupportedAccess }
    guard let saved = try await cloud.privateCloudDatabase.save(share) as? CKShare else {
      throw CareSyncError.invalidRecord
    }
    try await verifyAccount()
    try replica.cacheShare(saved, scope: .personal)
    notify()
    return saved
  }

  func acceptShare(_ metadata: CKShare.Metadata) async throws {
    try await verifyAccount()
    let share = try await cloud.accept(metadata)
    try await verifyAccount()
    try replica.allowAcceptedZone(share.recordID.zoneID)
    try replica.cacheShare(share, scope: .shared)
    try await sync()
  }
}
