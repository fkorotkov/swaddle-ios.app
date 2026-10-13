import AppIntents
import CoreSpotlight
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
protocol SiriIndexBackend {
    func clear() async throws
    func delete(ids: [String]) async throws
    func index(_ documents: [CareSearchDocument], snapshot: FamilySnapshot) async throws
}

@MainActor
final class SpotlightCareIndex: NSObject, SiriIndexBackend, CSSearchableIndexDelegate {
    static let name = "SwaddleCareHistory"
    private let spotlight = CSSearchableIndex(name: name, protectionClass: .complete)
    override init() {
        super.init()
        spotlight.indexDelegate = self
    }
    nonisolated func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexAllSearchableItemsWithAcknowledgementHandler acknowledgementHandler: @escaping () -> Void) {
        Task { @MainActor in
            await LogStore.shared.reindexSiriDiscovery()
            acknowledgementHandler()
        }
    }
    nonisolated func searchableIndex(_ searchableIndex: CSSearchableIndex, reindexSearchableItemsWithIdentifiers identifiers: [String], acknowledgementHandler: @escaping () -> Void) {
        // A full refresh also removes IDs for content that is no longer accessible.
        Task { @MainActor in
            await LogStore.shared.reindexSiriDiscovery()
            acknowledgementHandler()
        }
    }
    func clear() async throws { try await spotlight.deleteAllSearchableItems() }
    func delete(ids: [String]) async throws { if !ids.isEmpty { try await spotlight.deleteSearchableItems(withIdentifiers: ids) } }
    func index(_ documents: [CareSearchDocument], snapshot: FamilySnapshot) async throws {
        guard #available(iOS 27.0, *), let family = snapshot.family else { return }
        let items = documents.compactMap { document -> CSSearchableItem? in
            let attributes = CSSearchableItemAttributeSet(contentType: .text)
            if document.isCareNote, let child = snapshot.children.first(where: { $0.id == document.childID }) {
                attributes.associateAppEntity(CareNoteEntity(document: document, child: child, family: family))
            } else { attributes.associateAppEntity(CareRecordEntity(document)) }
            attributes.title = document.title; attributes.textContent = document.content
            attributes.contentCreationDate = document.occurredAt; attributes.contentModificationDate = document.modifiedAt
            attributes.relatedUniqueIdentifier = document.id
            let item = CSSearchableItem(uniqueIdentifier: document.id, domainIdentifier: family.id.uuidString, attributeSet: attributes)
            item.expirationDate = .distantFuture
            return item
        }
        if !items.isEmpty { try await spotlight.indexSearchableItems(items) }
    }
}

/// Serializes index changes, coalesces updates, and clears old-family content before publishing
/// a new family. Intent queries still recheck current access independently of this cache.
@MainActor @Observable
final class SiriDiscoveryIndex {
    private(set) var status = "Care history stays in Swaddle"
    @ObservationIgnored private let backend: any SiriIndexBackend
    @ObservationIgnored private var pending: FamilySnapshot?
    @ObservationIgnored private var completed: FamilySnapshot?
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var needsReindex = false
    init(backend: (any SiriIndexBackend)? = nil) { self.backend = backend ?? SpotlightCareIndex() }

    func update(snapshot: FamilySnapshot, force: Bool = false) {
        guard force || (snapshot != pending && (snapshot != completed || worker != nil)) else { return }
        needsReindex = needsReindex || force
        pending = snapshot
        guard worker == nil else { return }
        worker = Task { await drain() }
    }
    func flush() async { await worker?.value }

    private func drain() async {
        defer { worker = nil }
        while let snapshot = pending {
            pending = nil
            let reindex = needsReindex
            needsReindex = false
            let documents = CareSearchCatalog.documents(in: snapshot)
            status = snapshot.family == nil ? "Removing care history from Siri & Search…" : "Updating care history…"
            do {
                if reindex || completed == nil || completed?.family?.id != snapshot.family?.id || snapshot.family == nil {
                    try await backend.clear()
                } else {
                    let current = Set(documents.map(\.id))
                    let previous = CareSearchCatalog.documents(in: completed!)
                    try await backend.delete(ids: previous.map(\.id).filter { !current.contains($0) })
                }
                let old: [CareSearchDocument]
                if !reindex, let completed, completed.family?.id == snapshot.family?.id {
                    old = CareSearchCatalog.documents(in: completed)
                } else { old = [] }
                let existing = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })
                let changed = documents.filter { existing[$0.id] != $0 }
                // If access changed while deletion was pending, process the newest state first.
                if let pending, pending.family?.id != snapshot.family?.id { completed = nil; continue }
                try await backend.index(changed, snapshot: snapshot)
                completed = snapshot
                status = snapshot.family == nil ? "Care history stays in Swaddle" : "\(documents.count) records available to Siri & Search"
            } catch {
                completed = nil
                status = "Search update needs a retry. Your care log is saved."
                // Do not leave partially updated data after a failed write.
                try? await backend.clear()
            }
        }
    }
}
