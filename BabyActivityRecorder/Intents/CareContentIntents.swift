import AppIntents
import Foundation
import UniformTypeIdentifiers

@available(iOS 27.0, *)
@AppIntent(schema: .system.searchInApp)
struct SearchCareHistoryIntent: ShowInAppSearchResultsIntent {
    static var isAssistantOnly: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var searchScopes: [StringSearchScope] { [.general] }
    var criteria: StringSearchCriteria
    @MainActor func perform() async throws -> some IntentResult {
        let store = try SiriContentAccess.current()
        store.siriNavigation = SiriNavigationRequest(destination: .search(criteria.term))
        return .result()
    }
}

@available(iOS 27.0, *)
@AppIntent(schema: .system.open)
struct OpenCareRecordIntent: OpenIntent {
    static var isAssistantOnly: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    var target: CareRecordEntity
    @MainActor func perform() async throws -> some IntentResult {
        let store = try SiriContentAccess.current()
        let document = try CareSearchCatalog.resolve(target.id, in: store.snapshot)
        store.siriNavigation = SiriNavigationRequest(destination: .record(document.id))
        return .result()
    }
}

@available(iOS 27.0, *)
@AppIntent(schema: .system.open)
struct OpenCareNoteIntent: OpenIntent {
    static var isAssistantOnly: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    var target: CareNoteEntity
    @MainActor func perform() async throws -> some IntentResult {
        let store = try SiriContentAccess.current()
        let document = try SiriContentAccess.note(target.id, in: store)
        store.siriNavigation = SiriNavigationRequest(destination: .record(document.id))
        return .result()
    }
}

@available(iOS 27.0, *)
@AppIntent(schema: .system.open)
struct OpenFeedingReportIntent: OpenIntent {
    static var isAssistantOnly: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    var target: FeedingReportEntity
    @MainActor func perform() async throws -> some IntentResult {
        let store = try SiriContentAccess.current()
        guard let key = FeedingReportID(target.id) else { throw LogError.message("This report is unavailable.") }
        _ = try key.report(in: store.snapshot, now: .now)
        store.siriNavigation = SiriNavigationRequest(destination: .report(familyID: key.child.familyID, childID: key.child.recordID, period: key.period))
        return .result()
    }
}

@available(iOS 27.0, *)
struct ReadCareRecordIntent: AppIntent {
    static var title: LocalizedStringResource { "Read a care record" }
    static var description: IntentDescription { "Read the current saved details of a care record, including its child or caregiver and time." }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Record") var record: CareRecordEntity
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text = try SiriContentAccess.record(record.id).content
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

@available(iOS 27.0, *)
@AppIntent(schema: .notes.createNote)
struct CreateCareNoteIntent {
    static var isAssistantOnly: Bool { true }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    var name: AttributedString
    var content: AttributedString?
    var attachments: [IntentFile]
    var isPinned: Bool
    var folder: CareNotesFolder?

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<CareNoteEntity> & ProvidesDialog {
        let store = try SiriContentAccess.current()
        guard attachments.isEmpty, !isPinned else { throw LogError.message("Care notes support plain text. Attachments and pinning aren’t supported.") }
        let childID: UUID?
        if let folder {
            guard let key = CareContentID(folder.id), key.familyID == store.snapshot.family?.id else { throw LogError.message("This child is no longer available in your family.") }
            childID = key.recordID
        } else if store.snapshot.children.count > 1 {
            let family = store.snapshot.family!
            let selected = try await $folder.requestDisambiguation(among: store.snapshot.children.map { CareNotesFolder(child: $0, family: family) }, dialog: "Which child is this note for?")
            childID = CareContentID(selected.id)?.recordID
        } else { childID = nil }
        // Resolve again after any dialogue, because sharing access may have changed.
        store.reload()
        try SiriContentAccess.validate(store)
        let activity = try SiriCareNoteWriter.save(name: String(name.characters), content: content.map { String($0.characters) }, childID: childID, store: store)
        let child = try LogRules.child(activity.childID, in: store.snapshot)
        let document = try CareSearchCatalog.resolve(CareContentID(familyID: child.familyID, recordID: activity.id).rawValue, in: store.snapshot)
        return .result(value: CareNoteEntity(document: document, child: child, family: store.snapshot.family!), dialog: "Saved a care note for \(child.name).")
    }
}

@MainActor
enum SiriCareNoteWriter {
    static func save(name: String, content: String?, childID: UUID?, store: LogStore) throws -> Activity {
        store.reload()
        try SiriContentAccess.validate(store)
        let child = try LogRules.child(childID, in: store.snapshot, ready: store.isReady)
        let text = [name, content ?? ""].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
        guard !text.isEmpty else { throw LogError.message("Say what you’d like to remember.") }
        let activity = Activity(familyID: child.familyID, childID: child.id, occurredAt: .now, authorID: store.caregiverID,
            source: "Siri", note: text, payload: .careNote)
        try store.save(.activity(activity))
        return activity
    }
}
