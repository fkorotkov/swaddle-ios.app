import AppIntents
import SwiftUI

struct SiriDestinationView: View {
    let store: LogStore
    let request: SiriNavigationRequest
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if !store.isReady || !store.siriDiscoveryEnabled {
                    ContentUnavailableView("Care history is unavailable", systemImage: "lock", description: Text("Check your family account and Siri preferences in Swaddle."))
                } else {
                    switch request.destination {
                    case .search(let query): CareSearchView(store: store, query: query)
                    case .record(let id): CareRecordDetailView(store: store, recordID: id)
                    case .report(let familyID, let childID, let period):
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            if let report = try? FeedingReportID(familyID: familyID, childID: childID, period: period).report(in: store.snapshot, now: context.date) {
                                ScrollView { FeedingSummarySnippet(report: report, unit: store.volumeUnit).padding() }
                                    .navigationTitle("Feeding report")
                            } else { ContentUnavailableView("Report unavailable", systemImage: "chart.bar", description: Text("This child is no longer available in your family.")) }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.privacySensitive()
    }
}

struct CareSearchView: View {
    let store: LogStore
    @State private var query: String
    init(store: LogStore, query: String = "") { self.store = store; self.query = query }
    private var results: [CareSearchDocument] {
        guard store.isReady, store.siriDiscoveryEnabled else { return [] }
        return CareSearchCatalog.matching(query, documents: CareSearchCatalog.documents(in: store.snapshot))
    }
    var body: some View {
        List {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                Section(query.isEmpty ? String(localized: "Recent records") : String(localized: "Matching records")) {
                    ForEach(results) { document in
                        NavigationLink {
                            CareRecordDetailView(store: store, recordID: document.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(document.displayTitle).font(.headline)
                                Text(document.dateLabel).font(.caption).foregroundStyle(.secondary)
                                Text(document.previewText).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                            }.padding(.vertical, 4)
                        }.modifier(CareRecordContext(document: document, store: store))
                    }
                }
            }
        }.navigationTitle("Care history").searchable(text: $query, prompt: "Name, activity, or note")
            .privacySensitive()
    }
}

struct CareRecordDetailView: View {
    let store: LogStore
    let recordID: String
    private var document: CareSearchDocument? {
        guard store.isReady, store.siriDiscoveryEnabled else { return nil }
        return try? CareSearchCatalog.resolve(recordID, in: store.snapshot)
    }
    var body: some View {
        Group {
            if let document {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(document.displayTitle).font(.title2.bold())
                        Text(document.dateLabel).font(.subheadline).foregroundStyle(.secondary)
                        Text(document.content).font(.body).textSelection(.enabled)
                        Text("Updated \(document.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }.modifier(CareRecordContext(document: document, store: store))
            } else {
                ContentUnavailableView("Record unavailable", systemImage: "doc.questionmark", description: Text("It may have been deleted, or your family access may have changed."))
            }
        }.background(LogStyle.canvas).navigationTitle("Care record").privacySensitive()
    }
}

struct CareRecordContext: ViewModifier {
    let document: CareSearchDocument?
    let store: LogStore
    func body(content: Content) -> some View {
        if #available(iOS 27.0, *), store.siriDiscoveryEnabled, let document, let family = store.snapshot.family {
            if document.isCareNote, let child = store.snapshot.children.first(where: { $0.id == document.childID }) {
                content.appEntityIdentifier(EntityIdentifier(for: CareNoteEntity(document: document, child: child, family: family)))
            } else { content.appEntityIdentifier(EntityIdentifier(for: CareRecordEntity(document))) }
        } else { content }
    }
}

struct FeedingReportContext: ViewModifier {
    let store: LogStore
    let child: ChildProfile
    let period: ReportPeriod
    let now: Date
    func body(content: Content) -> some View {
        if #available(iOS 27.0, *), store.siriDiscoveryEnabled {
            let key = FeedingReportID(familyID: child.familyID, childID: child.id, period: period)
            let report = FeedingReport(child: child, period: period, snapshot: store.snapshot, now: now)
            content.appEntityIdentifier(EntityIdentifier(for: FeedingReportEntity(key: key, report: report, unit: store.volumeUnit)))
        } else { content }
    }
}

#if DEBUG
#Preview("Care history") {
    @Previewable @State var store = PreviewData.siriStore()
    NavigationStack { CareSearchView(store: store, query: "Robin bottle") }.tint(LogStyle.forest)
}
#Preview("Care note") {
    @Previewable @State var store = PreviewData.siriStore()
    if let note = CareSearchCatalog.documents(in: store.snapshot).first(where: { $0.isCareNote }) {
        NavigationStack { CareRecordDetailView(store: store, recordID: note.id) }.tint(LogStyle.forest)
    }
}
#endif
