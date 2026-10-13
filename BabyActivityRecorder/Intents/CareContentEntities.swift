import AppIntents
import CoreSpotlight
import CoreTransferable
import UniformTypeIdentifiers

@MainActor
enum SiriContentAccess {
    static func current() throws -> LogStore {
        let store = LogStore.shared
        store.reload()
        try validate(store)
        return store
    }
    static func validate(_ store: LogStore) throws {
        guard store.isReady, store.snapshot.family != nil else { throw LogError.message("Your family is unavailable. Open Swaddle to check your account.") }
        guard store.siriDiscoveryEnabled else { throw LogError.message("Care history is turned off. Enable Care history in Siri & Search in Swaddle’s Settings.") }
    }
    static func documents() throws -> [CareSearchDocument] { CareSearchCatalog.documents(in: try current().snapshot) }
    static func record(_ id: String) throws -> CareSearchDocument { try CareSearchCatalog.resolve(id, in: current().snapshot) }
    static func note(_ id: String, in store: LogStore) throws -> CareSearchDocument {
        try validate(store)
        let document = try CareSearchCatalog.resolve(id, in: store.snapshot)
        guard document.isCareNote else { throw LogError.message("This care note is no longer available.") }
        return document
    }
    static func noteText(_ id: String) throws -> String { try note(id, in: current()).content }
    static func report(_ id: String) throws -> FeedingReport {
        guard let key = FeedingReportID(id) else { throw LogError.message("This feeding report is unavailable.") }
        return try key.report(in: current().snapshot, now: .now)
    }
    static func reportText(_ id: String) throws -> String {
        let store = try current()
        guard let key = FeedingReportID(id) else { throw LogError.message("This feeding report is unavailable.") }
        let report = try key.report(in: store.snapshot, now: .now)
        return report.spoken(unit: store.volumeUnit) + " Calculated at \(report.asOf.formatted())."
    }
}

@available(iOS 27.0, *)
struct CareRecordEntity: IndexedEntity, Transferable, SyncableEntity, OwnershipProvidingEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Care record" }
    static var defaultQuery: CareRecordQuery { CareRecordQuery() }
    let id: String
    @Property(title: "Title", indexingKey: \.title) var title: String
    @Property(title: "Recorded details", indexingKey: \.textContent) var content: String
    @Property(title: "Occurred at", indexingKey: \.contentCreationDate) var occurredAt: Date
    var ownership: EntityOwnership { .shared }
    var displayRepresentation: DisplayRepresentation { .init(title: "\(title)", subtitle: "\(content)") }
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title; attributes.textContent = content; attributes.contentCreationDate = occurredAt
        return attributes
    }
    init(_ document: CareSearchDocument) { id = document.id; title = document.title; content = document.content; occurredAt = document.occurredAt }
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { entity in
            Data(try await SiriContentAccess.record(entity.id).content.utf8)
        }
    }
}

@available(iOS 27.0, *)
struct CareRecordQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [CareRecordEntity] {
        let ids = Set(identifiers)
        return try SiriContentAccess.documents().filter { ids.contains($0.id) }.map(CareRecordEntity.init)
    }
    @MainActor func entities(matching string: String) async throws -> [CareRecordEntity] {
        try CareSearchCatalog.matching(string, documents: SiriContentAccess.documents()).map(CareRecordEntity.init)
    }
    @MainActor func suggestedEntities() async throws -> [CareRecordEntity] { try SiriContentAccess.documents().prefix(20).map(CareRecordEntity.init) }
}

@available(iOS 27.0, *)
@AppEntity(schema: .notes.account)
struct CareNotesAccount: SyncableEntity {
    static var defaultQuery: CareNotesAccountQuery { CareNotesAccountQuery() }
    let id: UUID
    var name: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
    init(id: UUID, name: String) { self.id = id; self.name = name }
}
@available(iOS 27.0, *)
struct CareNotesAccountQuery: EntityQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [CareNotesAccount] {
        let family = try SiriContentAccess.current().snapshot.family!
        return identifiers.contains(family.id) ? [CareNotesAccount(id: family.id, name: family.name)] : []
    }
}

@available(iOS 27.0, *)
@AppEntity(schema: .notes.folder)
struct CareNotesFolder: SyncableEntity {
    static var defaultQuery: CareNotesFolderQuery { CareNotesFolderQuery() }
    let id: String
    var name: String
    var parentFolder: CareNotesFolder?
    var account: CareNotesAccount?
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
    init(child: ChildProfile, family: Family) {
        id = CareContentID(familyID: family.id, recordID: child.id).rawValue
        name = child.name; parentFolder = nil; account = CareNotesAccount(id: family.id, name: family.name)
    }
}
@available(iOS 27.0, *)
struct CareNotesFolderQuery: EntityStringQuery {
    @MainActor func all() throws -> [CareNotesFolder] {
        let store = try SiriContentAccess.current()
        let family = store.snapshot.family!
        return store.snapshot.children.map { CareNotesFolder(child: $0, family: family) }
    }
    @MainActor func entities(for identifiers: [String]) async throws -> [CareNotesFolder] { try all().filter { identifiers.contains($0.id) } }
    @MainActor func entities(matching string: String) async throws -> [CareNotesFolder] { try all().filter { $0.name.localizedCaseInsensitiveContains(string) } }
    @MainActor func suggestedEntities() async throws -> [CareNotesFolder] { try all() }
}

@available(iOS 27.0, *)
@AppEntity(schema: .notes.note)
struct CareNoteEntity: IndexedEntity, Transferable, SyncableEntity, OwnershipProvidingEntity {
    static var defaultQuery: CareNoteEntityQuery { CareNoteEntityQuery() }
    let id: String
    var name: AttributedString
    var content: AttributedString?
    var attachments: [IntentFile]
    var isPinned: Bool
    var creationDate: Date?
    var modificationDate: Date?
    var folder: CareNotesFolder?
    var ownership: EntityOwnership { .shared }
    var displayRepresentation: DisplayRepresentation { .init(title: "\(String(name.characters))") }
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = String(name.characters)
        attributes.textContent = content.map { String($0.characters) }
        attributes.contentCreationDate = creationDate; attributes.contentModificationDate = modificationDate
        return attributes
    }
    init(document: CareSearchDocument, child: ChildProfile, family: Family) {
        // Care notes are plain text; their first line is their title.
        id = document.id; name = AttributedString(document.previewText); content = AttributedString(document.content)
        attachments = []; isPinned = false; creationDate = document.createdAt; modificationDate = document.modifiedAt
        folder = CareNotesFolder(child: child, family: family)
    }
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { entity in
            Data(try await SiriContentAccess.noteText(entity.id).utf8)
        }
    }
}

@available(iOS 27.0, *)
struct CareNoteEntityQuery: EntityStringQuery {
    @MainActor static func notes(in snapshot: FamilySnapshot) -> [CareNoteEntity] {
        guard let family = snapshot.family else { return [] }
        return CareSearchCatalog.documents(in: snapshot).compactMap { document in
            guard document.isCareNote, let child = snapshot.children.first(where: { $0.id == document.childID }) else { return nil }
            return CareNoteEntity(document: document, child: child, family: family)
        }
    }
    @MainActor func entities(for identifiers: [String]) async throws -> [CareNoteEntity] {
        let ids = Set(identifiers)
        return Self.notes(in: try SiriContentAccess.current().snapshot).filter { ids.contains($0.id) }
    }
    @MainActor func entities(matching string: String) async throws -> [CareNoteEntity] {
        let store = try SiriContentAccess.current()
        let notes = CareSearchCatalog.documents(in: store.snapshot).filter(\.isCareNote)
        let ids = Set(CareSearchCatalog.matching(string, documents: notes).map(\.id))
        return Self.notes(in: store.snapshot).filter { ids.contains($0.id) }
    }
    @MainActor func suggestedEntities() async throws -> [CareNoteEntity] { Array(Self.notes(in: try SiriContentAccess.current().snapshot).prefix(20)) }
}

@available(iOS 27.0, *)
struct FeedingReportEntity: AppEntity, Transferable, SyncableEntity, OwnershipProvidingEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Feeding report" }
    static var defaultQuery: FeedingReportQuery { FeedingReportQuery() }
    let id: String
    @Property(title: "Child") var childName: String
    @Property(title: "Period") var period: String
    @Property(title: "Summary") var summary: String
    @Property(title: "Calculated at") var asOf: Date
    @Property(title: "Reporting time zone") var timeZoneIdentifier: String
    @Property(title: "Breast milk, mL") var milkML: Double
    @Property(title: "Formula, mL") var formulaML: Double
    @Property(title: "Unrecorded split, mL") var unknownML: Double
    @Property(title: "Total bottle intake, mL") var totalML: Double
    @Property(title: "Bottle feeds") var bottleCount: Int
    @Property(title: "Breastfeeding minutes") var nursingMinutes: Double
    var ownership: EntityOwnership { .shared }
    var displayRepresentation: DisplayRepresentation { .init(title: "\(childName)’s feeding", subtitle: "\(period)") }
    init(key: FeedingReportID, report: FeedingReport, unit: VolumeUnit) {
        id = key.rawValue; childName = report.childName; period = report.period.title; summary = report.spoken(unit: unit); asOf = report.asOf
        timeZoneIdentifier = report.timeZoneIdentifier
        milkML = report.summary.milkML.double; formulaML = report.summary.formulaML.double
        unknownML = report.summary.unknownML.double; totalML = report.summary.totalML.double
        bottleCount = report.summary.bottles; nursingMinutes = report.summary.nursingSeconds / 60
    }
    // Never index a rolling total. Resolve the stable report ID and calculate again at use time.
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { entity in
            Data(try await SiriContentAccess.reportText(entity.id).utf8)
        }
    }
}
@available(iOS 27.0, *)
struct FeedingReportQuery: EntityQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [FeedingReportEntity] {
        let store = try SiriContentAccess.current()
        return identifiers.compactMap { id in
            guard let key = FeedingReportID(id), let report = try? key.report(in: store.snapshot, now: .now) else { return nil }
            return FeedingReportEntity(key: key, report: report, unit: store.volumeUnit)
        }
    }
    @MainActor func suggestedEntities() async throws -> [FeedingReportEntity] {
        let store = try SiriContentAccess.current(), snapshot = store.snapshot
        guard let family = snapshot.family else { return [] }
        return snapshot.children.map { child in
            let key = FeedingReportID(familyID: family.id, childID: child.id, period: .last24Hours)
            return FeedingReportEntity(key: key, report: FeedingReport(child: child, period: .last24Hours, snapshot: snapshot, now: .now), unit: store.volumeUnit)
        }
    }
}
