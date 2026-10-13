import CoreData
import CloudKit
import Foundation

@MainActor
final class PersistenceController {
    static let appGroup = "group.com.github.fkorotkov.LittleLog"
    nonisolated static let cloudContainer = "iCloud.com.github.fkorotkov.LittleLog"
    private(set) var container: NSPersistentCloudKitContainer
    let cloudEnabled: Bool
    private(set) var loadError: Error?
    private(set) var storeDirectory: URL?
    private(set) var usesCKSyncEngine = false
    private(set) var controlledSync: CareCloudSync?
    private(set) var migrationMessage: String?
  var migrationStage = "Not started"
  var legacySyncFailure: String?
  private(set) var migrationLastFailure: String?
    private var migrationTask: Task<Void, Error>?
    var context: NSManagedObjectContext { container.viewContext }
    var sharedStore: NSPersistentStore? { container.persistentStoreCoordinator.persistentStores.first { $0.url?.lastPathComponent == "Shared.sqlite" } }
    var privateStore: NSPersistentStore? { container.persistentStoreCoordinator.persistentStores.first { $0.url?.lastPathComponent == "Private.sqlite" } }

    init(inMemory: Bool = false, directory: URL? = nil) {
        #if targetEnvironment(simulator)
        cloudEnabled = false
        #else
        cloudEnabled = !inMemory && Bundle.main.object(forInfoDictionaryKey: "LittleLogCloudKitEnabled") as? Bool == true
        #endif
        container = NSPersistentCloudKitContainer(name: "LittleLog", managedObjectModel: Self.model())
        do {
            let directory = try inMemory ? FileManager.default.temporaryDirectory.appending(path: "LittleLogMemory") : directory ?? Self.directory()
            if !inMemory { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
            storeDirectory = directory
            let checkpoint = try inMemory ? nil : CareSyncJournal.read(from: directory.appending(path: "CareSync-v1.json"))
            usesCKSyncEngine = cloudEnabled && checkpoint?.active == true
            container.persistentStoreDescriptions = ["Private", "Shared"].map { name in
                let description = NSPersistentStoreDescription(url: directory.appending(path: "\(name).sqlite"))
                if inMemory { description.type = NSInMemoryStoreType }
                description.shouldAddStoreAsynchronously = false
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                #if os(iOS)
                description.setOption(FileProtectionType.completeUntilFirstUserAuthentication as NSObject, forKey: NSPersistentStoreFileProtectionKey)
                #endif
                if cloudEnabled && !usesCKSyncEngine {
                    let options = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudContainer)
                    options.databaseScope = name == "Private" ? .private : .shared
                    description.cloudKitContainerOptions = options
                }
                return description
            }
            container.loadPersistentStores { [weak self] _, error in
                if let error { self?.loadError = error }
            }
            context.automaticallyMergesChangesFromParent = true
            context.mergePolicy = NSMergePolicy.error
            context.transactionAuthor = "LittleLog"
            if cloudEnabled, let checkpoint, checkpoint.active {
                controlledSync = CareCloudSync(replica: CareSyncReplica(persistence: self, journal: checkpoint,
                    url: directory.appending(path: "CareSync-v1.json")))
            }
        } catch { loadError = error }
    }

    func save() throws {
        try context.save()
        controlledSync?.localSaveCompleted()
    }

    func discardMigrationBackup() throws {
        guard let backup = storeDirectory?.appending(path: "BeforeCKSyncEngine"),
              FileManager.default.fileExists(atPath: backup.path) else { return }
        try FileManager.default.removeItem(at: backup)
    }

    var hasCheckedForExistingFamily: Bool {
        guard cloudEnabled else { return true }
        if usesCKSyncEngine { return controlledSync?.replica.journal.initialDownloadComplete == true }
        return (try? CloudSyncMigration.importsHaveCompleted(self)) == true
    }

    func share(for objectID: NSManagedObjectID) throws -> CKShare? {
        if usesCKSyncEngine { return try controlledSync?.replica.share(for: objectID) }
        return try container.fetchShares(matching: [objectID])[objectID]
    }

    func recordID(for objectID: NSManagedObjectID) -> CKRecord.ID? {
        usesCKSyncEngine ? controlledSync?.replica.recordID(for: objectID) : container.recordID(for: objectID)
    }

    func canUpdateRecord(_ objectID: NSManagedObjectID) -> Bool {
        if !cloudEnabled { return true }
        if usesCKSyncEngine { return controlledSync?.replica.canEdit(objectID) ?? false }
        return container.canUpdateRecord(forManagedObjectWith: objectID)
    }

    func sync(account: String) async throws {
        guard cloudEnabled else { return }
        if let loadError { throw loadError }
        if !usesCKSyncEngine {
            if let migrationTask { try await migrationTask.value }
            else {
                let task = Task { @MainActor in
                    defer { self.migrationTask = nil }
          let plan = try await CloudSyncMigration.prepare(self, account: account)
          self.migrationStage = String(localized: "Switching sync engines")
          try await self.adopt(plan)
                }
                migrationTask = task
        do { try await task.value; migrationMessage = nil; migrationStage = String(localized: "Complete") }
                catch {
          migrationLastFailure =
            "\(migrationStage): \((error as NSError).domain) / \((error as NSError).code)"
                    migrationMessage = error.localizedDescription
                    NotificationCenter.default.post(name: .careSyncChanged, object: self)
                    throw error
                }
            }
        }
        if controlledSync == nil {
            guard let directory = storeDirectory else { throw CareSyncError.unavailable }
            let url = directory.appending(path: "CareSync-v1.json")
            var journal = try CareSyncJournal.read(from: url) ?? CareSyncJournal(account: account)
            guard journal.account == account else { throw CareSyncError.accountChanged }
            journal.active = true
            try journal.write(to: url)
            controlledSync = CareCloudSync(replica: CareSyncReplica(persistence: self, journal: journal, url: url))
            NotificationCenter.default.post(name: .careSyncChanged, object: self)
        }
        try await controlledSync?.sync()
    }

  func adopt(
    _ plan: CloudSyncMigration.Plan,
    resolve: ((CloudSyncMigration.Plan, PersistenceController) async throws -> CareSyncJournal)? =
      nil
  ) async throws {
        guard let directory = storeDirectory, !context.hasChanges else { throw CareSyncError.waitingForLegacy }
    let journal = plan.journal
        let checkpointURL = directory.appending(path: "CareSync-v1.json")
        // A prepared checkpoint is never opened alongside active legacy mirroring.
        try journal.write(to: checkpointURL)
        do {
            context.reset()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
            let backup = directory.appending(path: "BeforeCKSyncEngine", directoryHint: .isDirectory)
            let staging = directory.appending(path: "BeforeCKSyncEngine-\(UUID())", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            for name in ["Private.sqlite", "Private.sqlite-wal", "Private.sqlite-shm", "Shared.sqlite", "Shared.sqlite-wal", "Shared.sqlite-shm"] {
                let source = directory.appending(path: name), destination = staging.appending(path: name)
                if FileManager.default.fileExists(atPath: source.path) {
                    try FileManager.default.copyItem(at: source, to: destination)
                }
            }
            if FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.removeItem(at: backup) }
            try FileManager.default.moveItem(at: staging, to: backup)
      try reopenStores(mirroring: false)
      try CloudSyncMigration.verifyLocalCheckpoint(
        self, journal: journal, requiresAcknowledgement: false)
      var activated: CareSyncJournal
      if let resolve {
        activated = try await resolve(plan, self)
      } else {
        activated = try await CloudSyncMigration.finish(plan, persistence: self)
      }
      try CloudSyncMigration.verifyLocalCheckpoint(self, journal: activated)
            activated.active = true
            do { try activated.write(to: checkpointURL) }
            catch {
                // An atomic-write error may be reported after the rename. If
                // the verified checkpoint landed, never restart a second writer.
                guard let saved = try CareSyncJournal.read(from: checkpointURL), saved.active,
                      saved.account == journal.account else { throw error }
            }
            usesCKSyncEngine = true
        } catch {
            do {
                // Establish the inactive marker before allowing legacy mirroring
                // to resume. No care data or cloud mapping was modified here.
                try journal.write(to: checkpointURL)
                context.reset()
                for store in container.persistentStoreCoordinator.persistentStores {
                    try container.persistentStoreCoordinator.remove(store)
                }
        try reopenStores(mirroring: cloudEnabled)
            } catch {
                loadError = error
            }
            throw error
        }
    }

  private func reopenStores(mirroring: Bool) throws {
    // A new container and descriptions avoid carrying the old mirroring
    // delegate's private options into the store that CKSyncEngine owns.
    let descriptions = try container.persistentStoreDescriptions.map { old in
      guard let url = old.url else { throw CareSyncError.unavailable }
      let description = NSPersistentStoreDescription(url: url)
      description.type = old.type
      description.shouldAddStoreAsynchronously = false
      description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
      description.setOption(
        true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
      #if os(iOS)
        description.setOption(
          FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
          forKey: NSPersistentStoreFileProtectionKey)
      #endif
      if mirroring {
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudContainer)
        options.databaseScope = old.url?.lastPathComponent == "Shared.sqlite" ? .shared : .private
        description.cloudKitContainerOptions = options
      }
      return description
    }
    container = NSPersistentCloudKitContainer(
      name: "LittleLog", managedObjectModel: container.managedObjectModel)
    container.persistentStoreDescriptions = descriptions
    loadError = nil
    container.loadPersistentStores { [weak self] _, error in
      if let error { self?.loadError = error }
    }
    if let loadError { throw loadError }
    context.automaticallyMergesChangesFromParent = true
    context.mergePolicy = NSMergePolicy.error
    context.transactionAuthor = "LittleLog"
  }

  static func directory() throws -> URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appending(path: "LittleLog", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    nonisolated static func model() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let family = NSEntityDescription()
        family.name = "FamilyRoot"
        family.managedObjectClassName = "NSManagedObject"
        family.properties = [attribute("id", .UUIDAttributeType), attribute("name", .stringAttributeType), attribute("timeZone", .stringAttributeType), attribute("ownerID", .UUIDAttributeType)]
        let revision = NSEntityDescription()
        revision.name = "Revision"
        revision.managedObjectClassName = "NSManagedObject"
        revision.properties = [attribute("id", .UUIDAttributeType), attribute("recordID", .UUIDAttributeType), attribute("parentIDs", .binaryDataAttributeType), attribute("payload", .binaryDataAttributeType), attribute("date", .dateAttributeType), attribute("editorID", .UUIDAttributeType), attribute("tombstone", .booleanAttributeType, defaultValue: false)]
        let toFamily = NSRelationshipDescription()
        toFamily.name = "family"
        toFamily.destinationEntity = family
        toFamily.maxCount = 1
        toFamily.isOptional = true
        toFamily.deleteRule = .nullifyDeleteRule
        let toRevisions = NSRelationshipDescription()
        toRevisions.name = "revisions"
        toRevisions.destinationEntity = revision
        toRevisions.minCount = 0
        toRevisions.maxCount = 0
        toRevisions.isOptional = true
        toRevisions.deleteRule = .cascadeDeleteRule
        toFamily.inverseRelationship = toRevisions
        toRevisions.inverseRelationship = toFamily
        family.properties.append(toRevisions)
        revision.properties.append(toFamily)
        let preference = NSEntityDescription()
        preference.name = "PrivatePreference"
        preference.managedObjectClassName = "NSManagedObject"
        preference.properties = [attribute("key", .stringAttributeType), attribute("payload", .binaryDataAttributeType), attribute("date", .dateAttributeType)]
        // No relationship to Family: these stay in the owner's private CloudKit zone.
        model.entities = [family, revision, preference]
        return model
    }
    nonisolated private static func attribute(_ name: String, _ type: NSAttributeType, defaultValue: Any? = nil) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        if name == "tombstone" { attribute.renamingIdentifier = "deleted" }
        attribute.attributeType = type
        attribute.isOptional = true
        attribute.defaultValue = defaultValue
        return attribute
    }
}
