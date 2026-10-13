import Foundation
import CoreData
import CloudKit
import Observation
import WidgetKit
import CryptoKit
import AppIntents
import CoreSpotlight

@MainActor @Observable
final class LogStore {
    static let shared = LogStore()
    private(set) var snapshot = FamilySnapshot()
    private(set) var isReady = false
    private(set) var canEdit = true
    private(set) var errorMessage: String?
    private(set) var syncMessage = String(localized: "Saved on this iPhone")
    private(set) var lastSync: Date?
    private(set) var isSyncing = false
  private(set) var syncNeedsAttention = false
    private(set) var pendingUploadCount = 0
    private(set) var lastUpload: Date?
    var syncStatus: FamilySyncStatus {
        FamilySyncStatus(cloudEnabled: persistence.cloudEnabled, isSyncing: isSyncing,
                         pendingUploads: pendingUploadCount, needsAttention: syncNeedsAttention,
                         lastCheck: lastSync)
    }
    private(set) var caregiverIdentityReady = false
    private(set) var caregiverIdentityMessage: String?
    private(set) var caregiverIdentityDiagnostic: String?
    private(set) var isCheckingCaregiverIdentity = false
    private(set) var caregiverInvitationURL: URL?
    private(set) var caregiverInvitationStage = CaregiverInvitationStage.preparingFamily
    private(set) var caregiverInvitationExportCheck = "Not started"
    private(set) var lastPrivateExportStatus = "No completed export observed in this session"
    var selectedChildID: UUID? { didSet { defaults.set(selectedChildID?.uuidString, forKey: "selectedChild") } }
    var volumeUnit: VolumeUnit { didSet { defaults.set(volumeUnit.rawValue, forKey: "volumeUnit") } }
    var toast: String? {
        didSet { if toast == nil { pumpingCelebration = nil } }
    }
    private(set) var pumpingCelebration: PumpingPersonalRecord?
    @ObservationIgnored private var playedPumpingCelebrationID: UUID?

    func claimPumpingCelebrationMotion(_ id: UUID) -> Bool {
        guard pumpingCelebration?.id == id, playedPumpingCelebrationID != id else { return false }
        playedPumpingCelebrationID = id
        return true
    }
    private(set) var siriDiscoveryEnabled = false
    var siriNavigation: SiriNavigationRequest?
    private(set) var undoID: UUID?
    private(set) var undoDeadline: Date?
    @ObservationIgnored let persistence: PersistenceController
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var accountBlocked = false
    @ObservationIgnored private var identity: String?
    @ObservationIgnored private var importingFamily = false
    @ObservationIgnored private var root: NSManagedObject?
    @ObservationIgnored private var revisions: [RecordRevision] = []
    @ObservationIgnored private let publishesWidgets: Bool
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var undoRecordIDs: [UUID] = []
    @ObservationIgnored private var undoBottlePreference: NSManagedObject?
    @ObservationIgnored private var widgetUndo: WidgetQuickLogCommand?
    @ObservationIgnored private var sharePreparation: (familyID: UUID, request: CloudSharePreparation)?
    @ObservationIgnored private var caregiverInvitationRequest: (key: String, request: CloudRequest<CaregiverInvitationDelivery>)?
    @ObservationIgnored private var acceptedCaregiverIdentity: VerifiedCaregiverInvitation?
    @ObservationIgnored private var caregiverIdentityRequest: (rootID: NSManagedObjectID, account: String, request: CloudRequest<CloudInvitationSnapshot>)?
    @ObservationIgnored private var siriIndex: SiriDiscoveryIndex?
  @ObservationIgnored private var nextLegacyRetry = Date.distantPast
    var caregiverID: UUID {
        if let text = defaults.string(forKey: "caregiverID"), let id = UUID(uuidString: text) { return id }
        let id = UUID(); defaults.set(id.uuidString, forKey: "caregiverID"); return id
    }
    var selectedChild: ChildProfile? { snapshot.children.first { $0.id == selectedChildID } ?? snapshot.children.first }
    var isOwner: Bool { snapshot.family?.ownerID == caregiverID }
    var myName: String { snapshot.caregiverName(caregiverID) }

    init(persistence: PersistenceController? = nil, defaults: UserDefaults? = nil, publishesWidgets: Bool = true) {
        self.publishesWidgets = publishesWidgets
        self.persistence = persistence ?? PersistenceController()
        self.defaults = defaults ?? .standard
        self.volumeUnit = VolumeUnit(rawValue: self.defaults.string(forKey: "volumeUnit") ?? "") ?? .ml
        self.selectedChildID = self.defaults.string(forKey: "selectedChild").flatMap(UUID.init(uuidString:))
        importingFamily = self.defaults.bool(forKey: "importingFamily")
        reload()
    updateSyncStatus()
        if self.persistence.cloudEnabled { Task { await self.checkAccount(); await self.syncCloud() } }
        observers.append(NotificationCenter.default.addObserver(forName: .careSyncChanged, object: self.persistence, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateSyncStatus(); self?.reload() }
        })
        // Notification delivery is synchronous, even with queue: .main. Core
        // Data can wait for its CloudKit worker during share setup, so forcing
        // that worker to wait for the main queue creates a deadlock. Receive
        // on the posting thread and schedule UI work asynchronously instead.
        observers.append(NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reload() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard !self.persistence.usesCKSyncEngine else { return }
                if event.type == .export, event.storeIdentifier == self.persistence.privateStore?.identifier,
                   event.endDate != nil {
                    if let error = event.error {
                        let detail = error as NSError
                        self.lastPrivateExportStatus = "Failed: \(detail.domain) / \(detail.code)"
                    } else {
                        self.lastPrivateExportStatus = event.succeeded ? "Completed" : "Not completed"
                    }
                }
          if let error = event.error {
            let detail = error as NSError
            self.persistence.legacySyncFailure = "\(detail.domain) / \(detail.code)"
            self.syncNeedsAttention = true
            self.syncMessage = String(localized: "iCloud needs attention: \(error.localizedDescription)")
          }
                else if event.endDate != nil, event.succeeded {
                    if event.type == .import, event.storeIdentifier == self.persistence.sharedStore?.identifier {
                        self.importingFamily = false
                        self.defaults.set(false, forKey: "importingFamily")
                    }
            // A setup or export event does not prove that both family
            // databases have downloaded successfully.
            self.syncMessage = self.persistence.migrationMessage ?? String(localized: "Preparing iCloud sync upgrade")
                    self.reload()
                    // A successful legacy export may make the handoff eligible.
            if (event.type == .export || event.type == .import), Date.now >= self.nextLegacyRetry {
              self.nextLegacyRetry = .now.addingTimeInterval(30)
              Task { await self.syncCloud() }
            }
                }
                else { self.syncMessage = String(localized: "Sharing pending") }
            }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.persistence.cloudEnabled else { return }
                self.accountBlocked = true
                self.persistence.controlledSync?.suspend()
                self.identity = nil
                self.acceptedCaregiverIdentity = nil
                self.caregiverIdentityRequest = nil
                self.caregiverInvitationURL = nil
                self.caregiverIdentityReady = false
                self.caregiverIdentityDiagnostic = nil
                self.isReady = false
                self.canEdit = false
                self.snapshot = FamilySnapshot()
                self.refreshSiriDiscovery()
                if self.publishesWidgets {
                    WidgetCache.write(snapshot: self.snapshot)
                    LittleLogShortcuts.updateAppShortcutParameters()
                }
                await self.checkAccount()
            }
        })
    }

    func syncCloud() async {
        guard persistence.cloudEnabled, !accountBlocked else { return }
        if !persistence.usesCKSyncEngine,
           sharePreparation?.request.isRunning == true || caregiverInvitationRequest?.request.isRunning == true { return }
        if identity == nil { await checkAccount() }
        guard let identity, !accountBlocked else { return }
        isSyncing = true
        defer { updateSyncStatus(); isSyncing = false; reload() }
        do {
            try await persistence.sync(account: identity)
            if importingFamily, persistence.usesCKSyncEngine {
                importingFamily = false
                defaults.set(false, forKey: "importingFamily")
            }
        } catch { syncMessage = error.localizedDescription }
    }

    private func updateSyncStatus() {
        guard persistence.cloudEnabled else { return }
    defer {
      // A local, identifier-free support snapshot can also be retrieved
      // from a connected phone without accessing its care database.
      if let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
        try? Data(syncDiagnostic.utf8).write(
          to: cache.appending(path: "SwaddleSyncDiagnostics.txt"),
          options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

      }
    }
        if let sync = persistence.controlledSync {
            syncMessage = sync.message
            isSyncing = sync.isSyncing
            pendingUploadCount = sync.replica.journal.pendingCount
            lastUpload = sync.replica.journal.lastUpload
            lastSync = sync.replica.journal.lastDownload
      // Queued local writes and an initial fetch are normal background work.
      syncNeedsAttention = sync.failure != nil || accountBlocked
    } else {
      syncNeedsAttention = persistence.legacySyncFailure != nil || accountBlocked
      lastSync = nil
      syncMessage = persistence.migrationMessage ?? String(localized: "Preparing iCloud sync upgrade")
    }
  }

  /// Shareable diagnostics deliberately exclude names, account IDs, record
  /// contents, invitation links, and CloudKit error userInfo.
  var syncDiagnostic: String {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    var lines = [
      "Swaddle \(version) (\(build)) · iCloud sync",
      "System: \(ProcessInfo.processInfo.operatingSystemVersionString)",
      "Engine: \(persistence.usesCKSyncEngine ? "CKSyncEngine" : "Core Data handoff")",
      "Handoff stage: \(persistence.migrationStage)",
      "Last handoff failure: \(persistence.migrationLastFailure ?? "None observed this launch")",
      "Previous sync error: \(persistence.legacySyncFailure ?? "None observed this launch")",
      "Previous private export: \(lastPrivateExportStatus)",
      "Local revisions: \(revisions.count)",
      "Caregiver profiles: \(snapshot.caregivers.count)",
    ]
    if persistence.cloudEnabled, !persistence.usesCKSyncEngine {
      for entity in ["FamilyRoot", "Revision", "PrivatePreference"] {
        if let objects = try? persistence.context.fetch(
          NSFetchRequest<NSManagedObject>(entityName: entity))
        {
          let mapped = objects.filter { persistence.recordID(for: $0.objectID) != nil }.count
          lines.append("\(entity) mapped: \(mapped) / \(objects.count)")
        }
      }
    }
    if let sync = persistence.controlledSync {
      lines.append("Pending uploads: \(sync.replica.journal.pendingCount)")
      lines.append("Pending downloads: \(sync.replica.journal.incoming.count)")
      lines.append(
        "Retained legacy copies: \(sync.replica.journal.retainedLegacyRecords?.count ?? 0)")
      for entity in ["FamilyRoot", "Revision", "PrivatePreference"] {
        lines.append(
          "\(entity) uploads: \(sync.replica.journal.entries.values.filter { $0.baseline.entity == entity && ($0.pending != nil || $0.deleting) }.count)"
        )
      }
      for scope in CareCloudScope.allCases {
        lines.append(
          "\(scope.rawValue) mapped records: \(sync.replica.journal.entries.values.filter { $0.baseline.id.scope == scope }.count)"
        )
      }
      if let error = sync.failure as NSError? {
        lines.append("Sync error: \(error.domain) / \(error.code)")
      }
    }
    return lines.joined(separator: "\n")
    }

    func checkAccount() async {
        guard persistence.cloudEnabled else { return }
        do {
            let recordID = try await CKContainer(identifier: PersistenceController.cloudContainer).userRecordID()
            let account = Self.cloudIdentity(recordID)
            if let prior = defaults.string(forKey: "cloudAccount"), prior != account {
                accountBlocked = true; isReady = false
                snapshot = FamilySnapshot()
                refreshSiriDiscovery()
                if publishesWidgets {
                    WidgetCache.write(snapshot: snapshot)
                    LittleLogShortcuts.updateAppShortcutParameters()
                }
                errorMessage = String(localized: "This log belongs to a different Apple Account. Sign back into the original account to continue. Your local records are preserved.")
                return
            }
            defaults.set(account, forKey: "cloudAccount")
            identity = account; accountBlocked = false
            reload()
            if let existing = snapshot.caregivers.first(where: { $0.cloudIdentity == account }) {
                defaults.set(existing.id.uuidString, forKey: "caregiverID")
            } else if var me = snapshot.caregivers.first(where: { $0.id == caregiverID }), canEdit {
                me.cloudIdentity = account
                try save(.caregiver(me))
            }
        } catch {
            syncNeedsAttention = true
            if accountBlocked { isReady = false; errorMessage = String(localized: "Check your iCloud account before opening this shared log.") }
            else { syncMessage = String(localized: "Saved locally · iCloud unavailable") }
        }
    }

    func reload() {
        defer { refreshSiriDiscovery() }
        guard !accountBlocked else { isReady = false; return }
        guard !importingFamily else { isReady = false; errorMessage = String(localized: "Importing your family from iCloud…"); return }
        do {
            if let error = persistence.loadError { throw error }
            let context = persistence.context
            context.refreshAllObjects()
            let roots = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "FamilyRoot"))
            let preferred = defaults.string(forKey: "familyID").flatMap(UUID.init(uuidString:))
            let families = roots.filter { $0.value(forKey: "id") != nil }
            root = families.first { $0.value(forKey: "id") as? UUID == preferred } ?? (families.count == 1 ? families.first : nil)
            guard let root, let id = root.value(forKey: "id") as? UUID,
                  let ownerID = root.value(forKey: "ownerID") as? UUID else {
                let hadChildren = !snapshot.children.isEmpty
                snapshot = FamilySnapshot()
                revisions = []
                if !persistence.hasCheckedForExistingFamily {
                    isReady = false
                    errorMessage = String(localized: "Checking iCloud for your family…")
                    return
                }
                isReady = true
                canEdit = true
                errorMessage = nil
                if families.count > 1 { throw LogError.message(String(localized: "More than one family is available. Resolve family membership before recording.")) }
                if publishesWidgets { WidgetCache.write(snapshot: snapshot) }
                if publishesWidgets, hadChildren { LittleLogShortcuts.updateAppShortcutParameters() }
                return
            }
            defaults.set(id.uuidString, forKey: "familyID")
            let family = Family(id: id, name: root.value(forKey: "name") as? String ?? "Our family", timeZoneIdentifier: root.value(forKey: "timeZone") as? String ?? TimeZone.current.identifier, ownerID: ownerID)
            let request = NSFetchRequest<NSManagedObject>(entityName: "Revision")
            request.predicate = NSPredicate(format: "family == %@", root)
            revisions = try context.fetch(request).map { object in
                guard let data = object.value(forKey: "payload") as? Data,
                      let revisionID = object.value(forKey: "id") as? UUID,
                      let recordID = object.value(forKey: "recordID") as? UUID,
                      let date = object.value(forKey: "date") as? Date,
                      let editorID = object.value(forKey: "editorID") as? UUID else { throw LogError.message(String(localized: "A record couldn’t be read. Your saved data has been preserved.")) }
                let payload = try JSONDecoder().decode(RecordEnvelope.self, from: data)
                guard RecordEnvelope.supportedVersions.contains(payload.version) else {
                    throw LogError.message(String(localized: "Update Swaddle to read this family’s newer records."))
                }
                let parents = try (object.value(forKey: "parentIDs") as? Data).map { try JSONDecoder().decode(Set<UUID>.self, from: $0) } ?? []
                return RecordRevision(id: revisionID, recordID: recordID, parentIDs: parents, value: payload.value, date: date, editorID: editorID, deleted: object.value(forKey: "tombstone") as? Bool ?? false)
            }
            let priorChildren = snapshot.children
            snapshot = FamilySnapshot(family: family, records: RevisionProjection.project(revisions))
            if let celebration = pumpingCelebration,
               !snapshot.pumps.contains(where: { $0.id == celebration.id && $0.totalML == celebration.totalML }) {
                pumpingCelebration = nil
            }
            if publishesWidgets, priorChildren != snapshot.children { LittleLogShortcuts.updateAppShortcutParameters() }
            canEdit = !persistence.cloudEnabled || persistence.canUpdateRecord(root.objectID)
            caregiverIdentityReady = !persistence.cloudEnabled
            if let identity {
                let localShare = try persistence.cloudEnabled ? persistence.share(for: root.objectID) : nil
                caregiverInvitationURL = localShare?.url
                let participant = localShare.flatMap {
                    acceptedCaregiverIdentity?.identity(familyID: id, shareRecordID: $0.recordID, account: identity)
                }
                if try adoptCaregiverIdentity(account: identity, participant: participant) {
                    reload()
                    return
                }
                caregiverIdentityReady = snapshot.caregivers.contains { $0.id == caregiverID && $0.cloudIdentity == identity }
                    || participant != nil
            }
            isReady = true
            errorMessage = nil
            if !persistence.cloudEnabled { syncMessage = String(localized: "Saved on this iPhone") }
            if publishesWidgets { WidgetCache.write(snapshot: snapshot, actorID: caregiverID, canRecord: isReady && canEdit && snapshot.caregivers.contains { $0.id == caregiverID }) }
        } catch { errorMessage = error.localizedDescription; isReady = false }
    }

    func setSiriDiscoveryEnabled(_ enabled: Bool) throws {
        guard #available(iOS 27.0, *) else { throw LogError.message(String(localized: "Care history discovery requires iOS 27. Voice logging and feeding answers remain available.")) }
        guard isReady, let family = snapshot.family else { throw LogError.message(String(localized: "Open your family before changing access.")) }
        defaults.set(enabled, forKey: "siri.discovery.\(family.id.uuidString)")
        refreshSiriDiscovery()
    }

    var siriDiscoveryStatus: String { siriIndex?.status ?? (siriDiscoveryEnabled ? String(localized: "Care history is enabled on this device") : String(localized: "Care history stays in Swaddle")) }

    func reindexSiriDiscovery() async {
        reload()
        siriIndex?.update(snapshot: siriDiscoveryEnabled ? snapshot : FamilySnapshot(), force: true)
        await siriIndex?.flush()
    }

    func openSearchActivity(_ activity: NSUserActivity) {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
        do {
            reload()
            try SiriContentAccess.validate(self)
            let document = try CareSearchCatalog.resolve(id, in: snapshot)
            siriNavigation = SiriNavigationRequest(destination: .record(document.id))
        } catch { report(error) }
    }

    private func refreshSiriDiscovery() {
        guard #available(iOS 27.0, *) else {
            siriDiscoveryEnabled = false
            siriNavigation = nil
            return
        }
        // An absent preference enables discovery; an explicit opt-out survives reloads.
        let allowed = !accountBlocked && isReady && snapshot.family.map {
            defaults.object(forKey: "siri.discovery.\($0.id.uuidString)") as? Bool ?? true
        } == true
        siriDiscoveryEnabled = allowed
        if !allowed { siriNavigation = nil }
        guard publishesWidgets else { return }
        if siriIndex == nil { siriIndex = SiriDiscoveryIndex() }
        siriIndex?.update(snapshot: allowed ? snapshot : FamilySnapshot())
    }

    func createFamily(childName: String, caregiverName: String, mother: Bool, unit: VolumeUnit, gender: ChildGender? = nil) throws {
        guard snapshot.family == nil, root == nil else { throw LogError.message(String(localized: "You already belong to a family.")) }
        guard !childName.trimmingCharacters(in: .whitespaces).isEmpty, !caregiverName.trimmingCharacters(in: .whitespaces).isEmpty else { throw LogError.message(String(localized: "Enter your name and your child’s name.")) }
        if let error = persistence.loadError { throw error }
        let context = persistence.context
        let familyID = UUID()
        let family = NSEntityDescription.insertNewObject(forEntityName: "FamilyRoot", into: context)
        family.setValue(familyID, forKey: "id")
        family.setValue("Our family", forKey: "name")
        family.setValue(TimeZone.current.identifier, forKey: "timeZone")
        family.setValue(caregiverID, forKey: "ownerID")
        if let store = persistence.privateStore { context.assign(family, to: store) }
        let child = ChildProfile(familyID: familyID, name: childName.trimmingCharacters(in: .whitespacesAndNewlines), gender: gender)
        let caregiver = Caregiver(id: caregiverID, familyID: familyID, name: caregiverName.trimmingCharacters(in: .whitespacesAndNewlines), isMother: mother, cloudIdentity: identity)
        do {
            try insert(.child(child), root: family, parents: [], commandID: UUID())
            try insert(.caregiver(caregiver), root: family, parents: [], commandID: UUID())
            try persistence.save()
            defaults.set(familyID.uuidString, forKey: "familyID")
            volumeUnit = unit
            if publishesWidgets, WidgetCache.defaults.object(forKey: "widgetVolumeUnit") == nil { WidgetCache.setUnit(unit) }
            selectedChildID = child.id
            reload()
        } catch { context.rollback(); throw error }
    }

    /// Append-only revisions retain concurrent edits. A command ID is stable across a retry.
    func save(_ value: RecordValue, parentIDs: Set<UUID>? = nil, commandID: UUID = UUID(), deleted: Bool = false, rememberBottle: Bool = false, restoring: Bool = false) throws {
        reload()
        guard isReady, let root else { throw LogError.message(errorMessage ?? String(localized: "Set up your family first.")) }
        guard canEdit else { throw LogError.message(String(localized: "This family is shared with view-only access.")) }
        if revisions.contains(where: { $0.id == commandID }) { return }
        let previous = snapshot.record(value.id)
        if previous?.isDeleted == true && !deleted && !restoring { throw LogError.message(String(localized: "This entry was deleted. Use Review edits & deleted entries to restore it explicitly.")) }
        var prepared = CaregiverMergeRules.preparing(
            value, previous: previous?.revision.value, in: snapshot)
        if case .caregiver(let person) = value {
            if person.mergedIntoID != nil {
                throw LogError.message(
                    String(localized: "Use Merge caregiver profiles to combine profiles, or Separate profiles to undo a merge.")
                )
            }
            if previous?.heads.contains(where: {
                if case .caregiver(let head) = $0.value { return head.mergedIntoID != nil }
                return false
            }) == true, !isOwner {
                throw LogError.message(String(localized: "Only the family owner can change a profile merge."))
            }
            if deleted {
                prepared = .caregiver(
                    try CaregiverDeletionRules.validate(
                        person.id, in: snapshot, actorID: caregiverID,
                        canEdit: canEdit, resolvingDeletion: restoring && previous?.isDeleted == true))
            } else if restoring, previous?.isDeleted == true {
                try CaregiverDeletionRules.validateRestoration(
                    person, in: snapshot, actorID: caregiverID, canEdit: canEdit)
            }
        }
        if !deleted { try LogRules.validate(prepared, in: snapshot, now: .now) }
        let pumpCelebration: PumpingPersonalRecord?
        if previous == nil, !deleted, !restoring, case .pumping(let session) = prepared {
            pumpCelebration = PumpingPersonalRecord.detect(
                newSession: session, in: snapshot, actorID: caregiverID, at: .now)
        } else { pumpCelebration = nil }
        let parents = parentIDs ?? Set(previous?.heads.map(\.id) ?? [])
        var newBottlePreference: NSManagedObject?
        do {
            if case .caregiver(var person) = value, person.id == caregiverID { person.cloudIdentity = identity ?? person.cloudIdentity; prepared = .caregiver(person) }
            try insert(prepared, root: root, parents: parents, commandID: commandID, deleted: deleted)
            if rememberBottle, !deleted, previous == nil, case .activity(let a) = value, case .bottle(let bottle) = a.payload, a.authorID == caregiverID {
                let preference = NSEntityDescription.insertNewObject(forEntityName: "PrivatePreference", into: persistence.context)
                if let privateStore = persistence.privateStore { persistence.context.assign(preference, to: privateStore) }
                preference.setValue(bottleKey(childID: a.childID), forKey: "key")
                preference.setValue(try JSONEncoder().encode(bottle), forKey: "payload")
                preference.setValue(Date.now, forKey: "date")
                newBottlePreference = preference
            }
            try persistence.save()
        } catch { persistence.context.rollback(); throw error }
        if previous == nil && !deleted { armUndo([value.id], bottlePreference: newBottlePreference) }
        pumpingCelebration = pumpCelebration
        syncMessage = persistence.cloudEnabled ? String(localized: "Saved on this iPhone · Sharing pending") : String(localized: "Saved on this iPhone")
        reload()
    }

    /// Launch links are authenticated locally before allowing any care-record write.
    @discardableResult
    func openWidgetDiaper(_ url: URL, signingKey: Data? = nil) throws -> UUID {
        guard let key = signingKey ?? WidgetCache.signingKey else { throw WidgetQuickLogCommand.invalidLink }
        let command = try WidgetQuickLogCommand.resolve(url, signingKey: key)
        reload()
        guard command.actorID == caregiverID else {
            throw LogError.message(String(localized: "Your caregiver profile changed. Open this widget again after it refreshes."))
        }
        let child = try WidgetQuickLogRules.child(target: command.target, in: snapshot, ready: isReady,
                                                  canEdit: canEdit, actorID: caregiverID)
        if command.undo {
            try undoWidgetDiaper(target: command.target, action: command.action, recordID: command.commandID)
            clearWidgetUndo()
            toast = String(localized: "Entry undone")
        } else {
            try recordWidgetDiaper(target: command.target, action: command.action, commandID: command.commandID,
                                  source: command.recordingSource)
            if let record = snapshot.record(command.commandID), !record.isDeleted {
                if let receipt = WidgetQuickLogRules.receipt(for: record, actorID: caregiverID), receipt.canUndo(at: .now) {
                    armUndo([command.commandID])
                    widgetUndo = command
                } else { clearWidgetUndo() }
                toast = String(localized: "\(command.action.diaper?.title ?? command.action.title) saved for \(child.name)")
            } else {
                clearWidgetUndo()
                toast = String(localized: "This entry was already undone")
            }
        }
        selectedChildID = child.id
        if publishesWidgets { WidgetCache.setQuickLogFailure(nil, target: command.target, action: command.action.rawValue) }
        return child.id
    }

    private func clearWidgetUndo() {
        // Reuse the feedback lifetime without attaching an unrelated Undo action.
        armUndo([])
    }

    /// The timeline supplies a stable command ID, so repeated delivery cannot create another diaper.
    func recordWidgetDiaper(target: String, action: WidgetQuickAction, commandID: UUID, now: Date = .now,
                           source: WidgetQuickLogSource = .lockScreen) throws {
        reload()
        let child = try WidgetQuickLogRules.child(target: target, in: snapshot, ready: isReady,
                                                  canEdit: canEdit, actorID: caregiverID)
        guard let diaper = action.diaper else { throw LogError.message(String(localized: "Open the bottle editor to confirm the amount.")) }
        if let previous = revisions.first(where: { $0.id == commandID }) {
            guard case .activity(let activity) = previous.value, activity.id == commandID,
                  activity.childID == child.id, activity.familyID == child.familyID,
                  activity.source == source.rawValue, activity.authorID == caregiverID,
                  activity.payload == .diaper(diaper) else {
                throw LogError.message(String(localized: "This control is out of date. Open Swaddle and try again."))
            }
            // A delayed retry after Undo must not restore the deleted entry.
            return
        }
        let activity = Activity(id: commandID, familyID: child.familyID, childID: child.id,
                                occurredAt: now, createdAt: now, authorID: caregiverID,
                                source: source.rawValue, payload: .diaper(diaper))
        try save(.activity(activity), commandID: commandID)
    }

    func undoWidgetDiaper(target: String, action: WidgetQuickAction, recordID: UUID, now: Date = .now) throws {
        reload()
        let child = try WidgetQuickLogRules.child(target: target, in: snapshot, ready: isReady,
                                                  canEdit: canEdit, actorID: caregiverID)
        guard let record = snapshot.record(recordID),
              case .activity(let activity) = record.revision.value,
              activity.childID == child.id, activity.familyID == child.familyID,
              activity.authorID == caregiverID, WidgetQuickLogRules.isWidgetSource(activity.source),
              let diaper = action.diaper, activity.payload == .diaper(diaper) else {
            throw LogError.message(String(localized: "This entry can’t be undone from a widget. Review it in Swaddle."))
        }
        if record.isDeleted { return }
        guard let receipt = WidgetQuickLogRules.receipt(for: record, actorID: caregiverID), receipt.canUndo(at: now) else {
            throw LogError.message(String(localized: "This entry was edited or Undo expired. Review it in Swaddle."))
        }
        try save(record.revision.value, parentIDs: [recordID], deleted: true)
    }

    /// Commit a reviewed import as one transaction. Stable record IDs make a retry idempotent.
    func importActivities(_ activities: [Activity]) throws -> Int {
        reload()
        guard isReady, canEdit, let root else { throw LogError.message(String(localized: "This family is unavailable or view-only.")) }
        guard !activities.isEmpty, Set(activities.map(\.id)).count == activities.count,
              Set(activities.map(\.childID)).count == 1 else { throw LogError.message(String(localized: "Review entries for one child at a time.")) }
        let now = Date.now
        for activity in activities {
            guard activity.authorID == caregiverID else { throw LogError.message(String(localized: "Import entries using your own caregiver profile.")) }
            try LogRules.validate(.activity(activity), in: snapshot, now: now)
        }
        let pending = activities.filter { activity in !revisions.contains { $0.id == activity.id } }
        guard !pending.isEmpty else { return 0 }
        guard pending.allSatisfy({ snapshot.record($0.id) == nil }) else { throw LogError.message(String(localized: "An import identifier is already in use. Prepare a new review.")) }
        var identities = Set(snapshot.activities.filter { $0.childID == activities[0].childID }.compactMap(\.importIdentity))
        for activity in pending {
            if let identity = activity.importIdentity, !identities.insert(identity).inserted {
                throw LogError.message(String(localized: "An entry with this source and ID was already imported. Go back and prepare a new review; nothing was saved."))
            }
        }
        do {
            for activity in pending { try insert(.activity(activity), root: root, parents: [], commandID: activity.id) }
            try persistence.save()
        } catch { persistence.context.rollback(); throw error }
        armUndo(pending.map(\.id))
        syncMessage = persistence.cloudEnabled ? String(localized: "Saved on this iPhone · Sharing pending") : String(localized: "Saved on this iPhone")
        reload()
        return pending.count
    }

    /// Pump imports belong to one caregiver, independently of child intake and bottle defaults.
    func importPumpingSessions(_ sessions: [PumpSession]) throws -> Int {
        reload()
        guard isReady, canEdit, let root else { throw LogError.message(String(localized: "This family is unavailable or view-only.")) }
        let sessions = sessions.map { session -> PumpSession in
            var prepared = session
            prepared.motherID = snapshot.canonicalCaregiverID(session.motherID)
            return prepared
        }
        guard !sessions.isEmpty, Set(sessions.map(\.id)).count == sessions.count,
              Set(sessions.map(\.motherID)).count == 1 else { throw LogError.message(String(localized: "Review pumping sessions for one caregiver at a time.")) }
        let now = Date.now
        for session in sessions {
            guard session.authorID == caregiverID else { throw LogError.message(String(localized: "Import entries using your own caregiver profile.")) }
            try LogRules.validate(.pumping(session), in: snapshot, now: now)
        }
        let pending = sessions.filter { session in !revisions.contains { $0.id == session.id } }
        guard !pending.isEmpty else { return 0 }
        guard pending.allSatisfy({ snapshot.record($0.id) == nil }) else { throw LogError.message(String(localized: "An import identifier is already in use. Prepare a new review.")) }
        var identities = Set(snapshot.pumps.filter { $0.motherID == sessions[0].motherID }.compactMap(\.importIdentity))
        for session in pending {
            if let identity = session.importIdentity, !identities.insert(identity).inserted {
                throw LogError.message(String(localized: "A pumping session with this source and ID was already imported. Go back and prepare a new review; nothing was saved."))
            }
        }
        do {
            for session in pending { try insert(.pumping(session), root: root, parents: [], commandID: session.id) }
            try persistence.save()
        } catch { persistence.context.rollback(); throw error }
        armUndo(pending.map(\.id))
        syncMessage = persistence.cloudEnabled ? String(localized: "Saved on this iPhone · Sharing pending") : String(localized: "Saved on this iPhone")
        reload()
        return pending.count
    }

    private func armUndo(_ ids: [UUID], bottlePreference: NSManagedObject? = nil) {
        pumpingCelebration = nil
        widgetUndo = nil
        undoRecordIDs = ids; undoBottlePreference = bottlePreference
        undoID = ids.first; undoDeadline = .now.addingTimeInterval(10)
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.undoID = nil; self?.undoDeadline = nil; self?.undoRecordIDs = []; self?.undoBottlePreference = nil; self?.widgetUndo = nil; self?.toast = nil
        }
    }

    /// Presentation receipts stay on this device; they are not care records.
    func claimAgeCelebration(_ celebration: AgeCelebration) -> Bool {
        guard !defaults.bool(forKey: celebration.receiptKey) else { return false }
        defaults.set(true, forKey: celebration.receiptKey)
        return true
    }

    private func insert(_ value: RecordValue, root: NSManagedObject, parents: Set<UUID>, commandID: UUID, deleted: Bool = false, editorID: UUID? = nil) throws {
        let revision = NSEntityDescription.insertNewObject(forEntityName: "Revision", into: persistence.context)
        if let store = root.objectID.persistentStore { persistence.context.assign(revision, to: store) }
        revision.setValue(commandID, forKey: "id")
        revision.setValue(value.id, forKey: "recordID")
        revision.setValue(try JSONEncoder().encode(parents), forKey: "parentIDs")
        revision.setValue(try JSONEncoder().encode(RecordEnvelope(value: value)), forKey: "payload")
        revision.setValue(Date.now, forKey: "date")
        revision.setValue(editorID ?? caregiverID, forKey: "editorID")
        revision.setValue(deleted, forKey: "tombstone")
        revision.setValue(root, forKey: "family")
    }

    func mergeCaregivers(_ reviewed: CaregiverMergePlan) throws {
        reload()
        guard isReady, let root else { throw LogError.message(String(localized: "Your family is still loading.")) }
        let plan = try CaregiverMergeRules.plan(
            sourceID: reviewed.source.id, destinationID: reviewed.destination.id, in: snapshot,
            actorID: caregiverID, canEdit: canEdit)
        guard plan.sourceHeads == reviewed.sourceHeads,
            plan.destinationHeads == reviewed.destinationHeads
        else {
            throw LogError.message(String(localized: "A profile changed. Review the profiles again before merging."))
        }
        var alias = plan.source
        alias.mergedIntoID = plan.destination.id
        do {
            if snapshot.record(plan.destination.id)?.revision.value != .caregiver(plan.destination)
            {
                try insert(
                    .caregiver(plan.destination), root: root, parents: plan.destinationHeads,
                    commandID: UUID())
            }
            try insert(
                .caregiver(alias), root: root, parents: plan.sourceHeads, commandID: UUID(),
                deleted: true)
            try persistence.save()
        } catch { persistence.context.rollback(); throw error }
        // A creation Undo from before this action must not delete the kept profile.
        undoTask?.cancel(); undoID = nil; undoDeadline = nil; undoRecordIDs = [];
        undoBottlePreference = nil
        syncMessage =
            persistence.cloudEnabled
            ? String(localized: "Saved on this iPhone · Sharing pending") : String(localized: "Saved on this iPhone")
        reload()
        toast = String(localized: "Profiles merged · History kept")
    }

    func separateCaregiver(_ id: UUID) throws {
        reload()
        guard isReady, isOwner, canEdit, let record = snapshot.record(id),
            record.isDeleted, !record.hasConflict,
            case .caregiver(var person) = record.revision.value,
            person.mergedIntoID != nil, person.cloudIdentity == nil
        else {
            throw LogError.message(
                String(localized: "Only the family owner can separate an uncontested profile merge."))
        }
        person.mergedIntoID = nil
        // A duplicate reservation must never reclaim the kept profile's account.
        person.invitation = nil
        try save(.caregiver(person), parentIDs: Set(record.heads.map(\.id)), restoring: true)
        toast = String(localized: "Profiles separated · History kept")
    }

    func deleteCaregiver(_ id: UUID) throws {
        reload()
        let person = try CaregiverDeletionRules.validate(
            id, in: snapshot, actorID: caregiverID, canEdit: canEdit)
        guard snapshot.record(id)?.isDeleted != true else { return }
        try save(.caregiver(person), deleted: true)
        toast = String(localized: "Caregiver deleted · History kept")
    }
    func delete(_ record: ProjectedRecord) throws {
        if case .caregiver = record.revision.value {
            try deleteCaregiver(record.id)
        } else {
            try save(record.revision.value, parentIDs: Set(record.heads.map(\.id)), deleted: true)
        }
    }
    func resolve(_ record: ProjectedRecord, using revision: RecordRevision) throws {
        guard revision.recordID == record.id, history(for: record.id).contains(where: { $0.id == revision.id }) else {
            throw LogError.message(String(localized: "This version is no longer available."))
        }
        try save(revision.value, parentIDs: Set(record.heads.map(\.id)), deleted: revision.deleted, restoring: record.isDeleted)
    }
    func deleteFamily() throws {
        reload()
        guard isReady, isOwner, canEdit, let root, let familyID = snapshot.family?.id else {
            throw LogError.message(String(localized: "Only the family owner can delete the family."))
        }
        let context = persistence.context
        do {
            try persistence.discardMigrationBackup()
            let request = NSFetchRequest<NSManagedObject>(entityName: "PrivatePreference")
            request.predicate = NSPredicate(format: "key BEGINSWITH %@", "bottle.\(familyID.uuidString).")
            if let privateStore = persistence.privateStore { request.affectedStores = [privateStore] }
            for preference in try context.fetch(request) { context.delete(preference) }
            context.delete(root)
            try persistence.save()
        } catch { context.rollback(); throw error }
        defaults.removeObject(forKey: "familyID")
        selectedChildID = nil
        undoTask?.cancel(); undoID = nil; undoDeadline = nil; undoRecordIDs = []; undoBottlePreference = nil; toast = nil
        reload()
    }
    func undo() throws {
        guard undoID != nil, let deadline = undoDeadline, deadline > .now else { return }
        if let command = widgetUndo {
            try undoWidgetDiaper(target: command.target, action: command.action, recordID: command.commandID)
            clearWidgetUndo()
            toast = String(localized: "Entry undone")
            return
        }
        reload()
        guard isReady, canEdit, let root else { throw LogError.message(String(localized: "This family is unavailable or view-only.")) }
        let records = undoRecordIDs.compactMap { snapshot.record($0) }.filter { !$0.isDeleted }
        for record in records {
            if case .caregiver = record.revision.value {
                _ = try CaregiverDeletionRules.validate(
                    record.id, in: snapshot, actorID: caregiverID, canEdit: canEdit)
            }
        }
        do {
            for record in records { try insert(record.revision.value, root: root, parents: Set(record.heads.map(\.id)), commandID: UUID(), deleted: true) }
            // Undo the default written by this creation in the same transaction.
            // Earlier defaults and preferences from other devices remain intact.
            if let preference = undoBottlePreference,
               let objectID = persistence.container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: preference.objectID.uriRepresentation()),
               let current = try? persistence.context.existingObject(with: objectID), !current.isDeleted {
                persistence.context.delete(current)
            }
            try persistence.save()
        } catch { persistence.context.rollback(); throw error }
        undoID = nil; undoDeadline = nil; undoRecordIDs = []; undoBottlePreference = nil; toast = records.count > 1 ? String(localized: "Import undone") : String(localized: "Entry undone")
        reload()
    }
    func previousBottle(childID: UUID) -> Bottle? {
        let key = bottleKey(childID: childID)
        let request = NSFetchRequest<NSManagedObject>(entityName: "PrivatePreference")
        request.predicate = NSPredicate(format: "key == %@", key)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchLimit = 1
        if let store = persistence.privateStore { request.affectedStores = [store] }
        guard let data = try? persistence.context.fetch(request).first?.value(forKey: "payload") as? Data else { return nil }
        return try? JSONDecoder().decode(Bottle.self, from: data)
    }
    private func bottleKey(childID: UUID) -> String { "bottle.\(snapshot.family?.id.uuidString ?? "").\(childID).\(caregiverID)" }
    func history(for id: UUID) -> [RecordRevision] { revisions.filter { $0.recordID == id }.sorted { $0.date > $1.date } }
    func setReportingZone(_ identifier: String) throws {
        reload()
        guard canEdit, TimeZone(identifier: identifier) != nil, let root else { throw LogError.message(String(localized: "Choose a valid reporting time zone.")) }
        root.setValue(identifier, forKey: "timeZone")
        do { try persistence.save(); reload() } catch { persistence.context.rollback(); throw error }
    }
    func prepareShare() async throws -> CKShare {
        guard persistence.cloudEnabled else { throw LogError.message(String(localized: "iCloud sharing needs a signed device build with the Swaddle iCloud container enabled. Local logging is available in Simulator.")) }
        guard isReady, !accountBlocked, let root, let familyID = snapshot.family?.id else {
            throw LogError.message(String(localized: "Your family is unavailable. Please wait for iCloud to finish loading."))
        }
        if persistence.usesCKSyncEngine {
            guard let sync = persistence.controlledSync else { throw CareSyncError.unavailable }
            return try await sync.prepareShare(for: root.objectID)
        }
        if sharePreparation?.familyID != familyID {
            sharePreparation = (familyID, CloudSharePreparation())
        }
        guard let preparation = sharePreparation?.request else { throw CloudSharePreparationError.familyChanged }
        let share = try await preparation.value { completion in
            do {
                let existing = try persistence.share(for: root.objectID)
                if let existing, existing.url != nil {
                    completion(.success(existing))
                } else if !isOwner {
                    completion(.failure(LogError.message(String(localized: "This family’s sharing details are not available yet. Please try again after iCloud updates."))))
                } else if let existing {
                    exportShareForInvitation(existing, familyID: familyID, completion: completion)
                } else {
                    persistence.container.share([root], to: nil) { [weak self] _, share, _, error in
                        Task { @MainActor [weak self] in
                            if let error { completion(.failure(error)) }
                            else if let self, let share {
                                self.exportShareForInvitation(share, familyID: familyID, completion: completion)
                            } else {
                                completion(.failure(LogError.message(String(localized: "iCloud couldn’t prepare the invitation. Try again."))))
                            }
                        }
                    }
                }
            } catch { completion(.failure(error)) }
        }
        try Task.checkCancellation()
        guard isReady, !accountBlocked, snapshot.family?.id == familyID else {
            throw CloudSharePreparationError.familyChanged
        }
        return share
    }

    private func exportShareForInvitation(_ share: CKShare, familyID: UUID, completion: @escaping CloudSharePreparation.Completion) {
        guard isReady, !accountBlocked, isOwner, snapshot.family?.id == familyID,
              let privateStore = persistence.privateStore else {
            completion(.failure(CloudSharePreparationError.familyChanged))
            return
        }
        share[CKShare.SystemFieldKey.title] = "Swaddle · Our family" as CKRecordValue
        share.publicPermission = .none
        // share(_:to:) can finish before export. Persist metadata and wait for
        // the server's share URL before presenting UICloudSharingController.
        persistence.container.persistUpdatedShare(share, in: privateStore) { savedShare, error in
            if let error { completion(.failure(error)) }
            else if let savedShare, savedShare.url != nil { completion(.success(savedShare)) }
            else { completion(.failure(CloudSharePreparationError.invitationNotReady)) }
        }
    }
    func acceptShare(_ metadata: CKShare.Metadata) async throws {
        guard persistence.cloudEnabled, let sharedStore = persistence.sharedStore else { throw LogError.message(String(localized: "Open this invitation in a signed Swaddle build with iCloud enabled.")) }
        let existingShareID = try root.flatMap { try persistence.share(for: $0.objectID)?.recordID }
        // Reopening an imported invitation is a recovery action, not a no-op.
        let action = try CloudInvitationAction.resolve(hasFamily: root != nil, existingShareID: existingShareID,
                                                      incomingShareID: metadata.share.recordID, status: metadata.participantStatus)
        if action == .refreshIdentity {
            if persistence.usesCKSyncEngine { await syncCloud() }
            await refreshCaregiverIdentity(force: true)
            return
        }
        isReady = false
        acceptedCaregiverIdentity = nil
        caregiverIdentityReady = false
        importingFamily = true
        defaults.set(true, forKey: "importingFamily")
        do {
            if persistence.usesCKSyncEngine {
                if persistence.controlledSync == nil { await checkAccount(); await syncCloud() }
                guard let sync = persistence.controlledSync else { throw CareSyncError.unavailable }
                try await sync.acceptShare(metadata)
                importingFamily = false
                defaults.set(false, forKey: "importingFamily")
                reload()
                await refreshCaregiverIdentity(force: true)
                return
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                persistence.container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            // Acceptance schedules an import; only this shared store's completed import unlocks child resolution.
            reload()
        } catch {
            importingFamily = false
            defaults.set(false, forKey: "importingFamily")
            reload()
            throw error
        }
    }
    func report(_ error: Error) { errorMessage = error.localizedDescription }
    func clearError() { errorMessage = nil }

    nonisolated static func cloudIdentity(_ recordID: CKRecord.ID) -> String {
        SHA256.hash(data: Data(recordID.recordName.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Returns true only if a revision was written and the snapshot must reload.
    /// The same caregiver ID preserves every pumping session and its attribution.
    @discardableResult
    func adoptCaregiverIdentity(account: String, participant: AcceptedCaregiverIdentity?) throws -> Bool {
        guard let root else { return false }
        guard var person = try CaregiverInvitationRules.profile(for: account, participant: participant, in: snapshot) else { return false }
        var wrote = false
        if person.cloudIdentity != account, canEdit {
            person.cloudIdentity = account
            let parents = Set(snapshot.record(person.id)?.heads.map(\.id) ?? [])
            do {
                try insert(.caregiver(person), root: root, parents: parents, commandID: UUID(), editorID: person.id)
                try persistence.save()
                wrote = true
            } catch { persistence.context.rollback(); throw error }
        }
        defaults.set(person.id.uuidString, forKey: "caregiverID")
        return wrote
    }

    func refreshCaregiverIdentity(force: Bool = false) async {
        guard !isCheckingCaregiverIdentity else { return }
        isCheckingCaregiverIdentity = true
        defer { isCheckingCaregiverIdentity = false }
        caregiverIdentityMessage = nil
        caregiverIdentityDiagnostic = nil
        if identity == nil { await checkAccount() }
        else { reload() }
        guard persistence.cloudEnabled, force || !caregiverIdentityReady else { return }
        do {
            guard !accountBlocked, let account = identity, let root, let familyID = snapshot.family?.id,
                  let local = try persistence.share(for: root.objectID) else {
                throw CloudInvitationError.syncing
            }
            caregiverInvitationURL = local.url
            let rootID = root.objectID
            if caregiverIdentityRequest?.rootID != rootID || caregiverIdentityRequest?.account != account {
                caregiverIdentityRequest = (rootID, account, CloudRequest())
            }
            guard let request = caregiverIdentityRequest?.request else { return }
            let container = CKContainer(identifier: PersistenceController.cloudContainer)
            let database = root.objectID.persistentStore == persistence.sharedStore ? container.sharedCloudDatabase : container.privateCloudDatabase
            let result = try await request.value { completion in
                Task {
                    do {
                        let currentAccountID = try await container.userRecordID()
                        guard Self.cloudIdentity(currentAccountID) == account else {
                            throw CloudSharePreparationError.familyChanged
                        }
                        guard let share = try await database.record(for: local.recordID) as? CKShare else {
                            throw CloudInvitationError.participantUnavailable
                        }
                        // The database record contains participant identities;
                        // metadata supplies the current account's latest status.
                        // Do not require metadata to contain the full roster.
                        let metadata: CKShare.Metadata?
                        if let url = local.url { metadata = try await container.shareMetadata(for: url) }
                        else { metadata = nil }
                        if let metadata, metadata.share.recordID != share.recordID {
                            throw CloudSharePreparationError.familyChanged
                        }
                        guard Self.cloudIdentity(try await container.userRecordID()) == account else {
                            throw CloudSharePreparationError.familyChanged
                        }
                        if self.identity == account, self.snapshot.family?.id == familyID {
                            self.caregiverIdentityDiagnostic = self.invitationDiagnosticHeader + "\n"
                                + CloudInvitationSnapshot.diagnostics(share: share, metadata: metadata, account: account)
                        }
                        completion(.success(try CloudInvitationSnapshot(share: share, metadata: metadata)
                            .verifyingCurrentParticipant(account: account)))
                    } catch { completion(.failure(error)) }
                }
            }
            guard !accountBlocked, identity == account, snapshot.family?.id == familyID,
                  self.root?.objectID == rootID, result.recordID == local.recordID else {
                throw CloudSharePreparationError.familyChanged
            }
            acceptedCaregiverIdentity = nil
            let participant = try result.acceptedIdentity(account: account)
            acceptedCaregiverIdentity = VerifiedCaregiverInvitation(familyID: familyID, shareRecordID: result.recordID, participant: participant)
            reload()
            if !isReady { caregiverIdentityMessage = errorMessage }
        } catch is CancellationError {
            // Leaving the screen cancels the wait, not Core Data's work.
        } catch {
            caregiverIdentityMessage = error.localizedDescription
            let detail = error as NSError
            caregiverIdentityDiagnostic = (caregiverIdentityDiagnostic ?? invitationDiagnosticHeader)
                + "\nResult: \(detail.domain) / \(detail.code)"
        }
    }

    private var invitationDiagnosticHeader: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Swaddle \(version) (\(build)) · iCloud invitation\n\(ProcessInfo.processInfo.operatingSystemVersionString)"
    }

    var caregiverInvitationDiagnostic: String {
        """
        \(invitationDiagnosticHeader)
        Preparation stage: \(caregiverInvitationStage)
        Profile export check: \(caregiverInvitationExportCheck)
        Private store export: \(lastPrivateExportStatus)
        """
    }

    func createJoinedCaregiver(name: String, pumping: Bool) throws {
        reload()
        guard caregiverIdentityReady, let family = snapshot.family else {
            throw LogError.message(String(localized: "Wait for Swaddle to check your invitation before creating a profile."))
        }
        // A late import may have linked the existing profile while this form was open.
        guard !snapshot.caregivers.contains(where: { $0.id == caregiverID }) else { return }
        try save(.caregiver(Caregiver(id: caregiverID, familyID: family.id,
                                     name: name.trimmingCharacters(in: .whitespacesAndNewlines), isMother: pumping, cloudIdentity: identity)))
    }

    func reserveCaregiverInvitation(_ id: UUID, invitation: CaregiverInvitation, replacingRemovedInvitation: Bool = false) throws -> NSManagedObjectID {
        reload()
        guard isReady, canEdit, let root else { throw CloudSharePreparationError.familyChanged }
        let person = try CaregiverInvitationRules.reserving(id, for: invitation, in: snapshot,
                                                          actorID: caregiverID, replacingRemovedInvitation: replacingRemovedInvitation)
        if snapshot.caregivers.first(where: { $0.id == id })?.invitation != invitation {
            try save(.caregiver(person))
        }
        guard let revision = snapshot.record(id)?.revision else { throw CloudSharePreparationError.familyChanged }
        let request = NSFetchRequest<NSManagedObject>(entityName: "Revision")
        request.predicate = NSPredicate(format: "id == %@ AND family == %@", revision.id as CVarArg, root)
        guard let object = try persistence.context.fetch(request).first else { throw CloudSharePreparationError.familyChanged }
        return object.objectID
    }

    func prepareCaregiverInvitation(caregiverID id: UUID, email: String) async throws -> CaregiverInvitationDelivery {
        let email = try CaregiverInvitationRules.email(email)
        guard persistence.cloudEnabled else { throw LogError.message(String(localized: "Invitations need a signed iPhone build with iCloud enabled.")) }
        guard isReady, isOwner, canEdit, let familyID = snapshot.family?.id else { throw CloudSharePreparationError.familyChanged }
        let key = "\(familyID):\(id):\(email.lowercased())"
        if caregiverInvitationRequest?.key != key {
            guard caregiverInvitationRequest?.request.isRunning != true else {
                throw LogError.message(String(localized: "Another invitation is still being prepared. Please try again shortly."))
            }
            caregiverInvitationRequest = (key, CloudRequest())
        }
        guard let request = caregiverInvitationRequest?.request else { throw CloudSharePreparationError.familyChanged }
        do {
            // Profile export has its own 45-second budget. Do not cut it off
            // with the old 30-second timeout for the entire multistep flow.
            return try await request.value(timeout: .seconds(90)) { completion in
                // Dismissing or timing out stops the UI wait. The authorized operation
                // still finishes consistently; a retry joins it instead of granting twice.
                Task { @MainActor in
                    do { completion(.success(try await self.createCaregiverInvitation(id, email: email, familyID: familyID))) }
                    catch { completion(.failure(error)) }
                }
            }
        } catch CloudSharePreparationError.timedOut {
            throw LogError.message(caregiverInvitationStage.waitingMessage)
        }
    }

    private func createCaregiverInvitation(_ id: UUID, email: String, familyID: UUID) async throws -> CaregiverInvitationDelivery {
        caregiverInvitationStage = .preparingFamily
        caregiverInvitationExportCheck = "Not started"
        let share = try await prepareShare()
        guard let privateStore = persistence.privateStore else { throw CloudSharePreparationError.familyChanged }
        caregiverInvitationStage = .findingAccount
        let fetched: [CKShare.Participant]
        if persistence.usesCKSyncEngine {
            fetched = [try await CKContainer(identifier: PersistenceController.cloudContainer).shareParticipant(forEmailAddress: email)]
        } else {
            fetched = try await withCheckedThrowingContinuation { continuation in
                persistence.container.fetchParticipants(matching: [CKUserIdentity.LookupInfo(emailAddress: email)], into: privateStore) { participants, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: participants ?? []) }
                }
            }
        }
        guard fetched.count == 1, let recipient = fetched.first else {
            throw LogError.message(String(localized: "iCloud couldn’t find a recipient for that address. Check their Apple Account email and try again."))
        }
        try validateInvitationContext(familyID)
        caregiverInvitationStage = .checkingAccess
        // Use the server copy so a retry preserves participants and permission
        // changes made in Apple's sharing controls or on another owner device.
        let database = CKContainer(identifier: PersistenceController.cloudContainer).privateCloudDatabase
        guard let current = try await database.record(for: share.recordID) as? CKShare,
              current.publicPermission == .none else { throw CloudSharePreparationError.invitationNotReady }
        try validateInvitationContext(familyID)
        let participant = current.participants.first(where: { $0.isEqual(recipient) }) ?? recipient
        guard participant.role != .owner else { throw LogError.message(String(localized: "That is your Apple Account. Invite the caregiver using their own account.")) }
        let invitation = CaregiverInvitation(shareRecordName: current.recordID.recordName, participantID: participant.participantID,
                                            accountIdentity: participant.userIdentity.userRecordID.map(Self.cloudIdentity))
        let prior = snapshot.caregivers.first(where: { $0.id == id })?.invitation
        let removed = prior.map { previous in
            previous.shareRecordName != current.recordID.recordName || !current.participants.contains { $0.participantID == previous.participantID }
        } ?? false
        let revisionID = try reserveCaregiverInvitation(id, invitation: invitation, replacingRemovedInvitation: removed)
        if CaregiverInvitationReuse.canReuseAcceptedLink(previous: prior, current: invitation,
                membership: .init(status: participant.acceptanceStatus, role: participant.role, permission: participant.permission),
                hasURL: current.url != nil), let url = current.url {
            // Apple already granted this exact participant access. A retry must
            // not wait for a newer local revision just to return the same link.
            caregiverInvitationExportCheck = "Existing accepted invitation; no new access requested"
            return CaregiverInvitationDelivery(url: url, caregiverName: snapshot.caregiverName(id), recipientEmail: email,
                                              alreadyAccepted: true)
        }
        caregiverInvitationStage = .syncingProfile
        // Make the reservation available to an immediately accepting recipient.
        // Otherwise the share could arrive before its profile and create a duplicate.
        try await waitForInvitationExport(revisionID, database: database, familyID: familyID)
        try validateInvitationContext(familyID)
        _ = try CaregiverInvitationRules.reserving(id, for: invitation, in: snapshot, actorID: caregiverID)
        guard snapshot.caregivers.first(where: { $0.id == id })?.invitation == invitation else {
            throw LogError.message(String(localized: "This caregiver’s invitation changed while syncing. Reopen the profile to continue."))
        }
        if current.participants.contains(where: { $0.isEqual(participant) && $0.permission == .readWrite }),
           let url = current.url {
            // An unchanged, server-verified invitation is already ready to send.
            // Re-exporting the same share can unnecessarily wait on iCloud.
            return CaregiverInvitationDelivery(url: url, caregiverName: snapshot.caregiverName(id), recipientEmail: email)
        }
        caregiverInvitationStage = .savingInvitation
        if !current.participants.contains(where: { $0.isEqual(participant) }) {
            participant.permission = .readWrite
            current.addParticipant(participant)
        } else if participant.permission != .readWrite {
            // A profile invitation explicitly offers editing, including pumping.
            participant.permission = .readWrite
        }
        let saved = try await saveShare(current)
        try validateInvitationContext(familyID)
        guard let url = saved.url,
              saved.participants.contains(where: { $0.isEqual(participant) && $0.permission == .readWrite }) else {
            throw CloudSharePreparationError.invitationNotReady
        }
        return CaregiverInvitationDelivery(url: url, caregiverName: snapshot.caregiverName(id), recipientEmail: email)
    }

    func saveShare(_ share: CKShare) async throws -> CKShare {
        if persistence.usesCKSyncEngine {
            guard let sync = persistence.controlledSync else { throw CareSyncError.unavailable }
            return try await sync.saveShare(share)
        }
        guard let privateStore = persistence.privateStore else { throw CareSyncError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            persistence.container.persistUpdatedShare(share, in: privateStore) { saved, error in
                if let error { continuation.resume(throwing: error) }
                else if let saved { continuation.resume(returning: saved) }
                else { continuation.resume(throwing: CloudSharePreparationError.invitationNotReady) }
            }
        }
    }

    private func validateInvitationContext(_ familyID: UUID) throws {
        reload()
        guard isReady, !accountBlocked, isOwner, canEdit, snapshot.family?.id == familyID else { throw CloudSharePreparationError.familyChanged }
    }

    private func waitForInvitationExport(_ objectID: NSManagedObjectID, database: CKDatabase, familyID: UUID) async throws {
        if persistence.usesCKSyncEngine {
            guard let sync = persistence.controlledSync else { throw CareSyncError.unavailable }
            try await sync.sync()
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(45))
        while ContinuousClock.now < deadline {
            try validateInvitationContext(familyID)
            if let recordID = persistence.recordID(for: objectID) {
                caregiverInvitationExportCheck = "Record mapping available; checking server"
                do {
                    _ = try await database.record(for: recordID)
                    caregiverInvitationExportCheck = "Record found on server"
                    return
                } catch let error as CKError where error.code == .unknownItem {
                    caregiverInvitationExportCheck = "Record mapping available; server record not found"
                } catch {
                    let detail = error as NSError
                    caregiverInvitationExportCheck = "Server lookup failed: \(detail.domain) / \(detail.code)"
                    throw error
                }
            } else {
                caregiverInvitationExportCheck = "Waiting for Core Data record mapping"
            }
            try await Task.sleep(for: .seconds(2))
        }
        throw LogError.message(String(localized: "The caregiver profile is still syncing. Try again shortly; its history is safe."))
    }
}

struct CaregiverInvitationDelivery: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let caregiverName: String
    let recipientEmail: String
    var alreadyAccepted = false
}
