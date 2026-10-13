import AppIntents
import SwiftUI

nonisolated extension ReportPeriod: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Time period" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.last24Hours: "Last 24 hours", .today: "Today", .yesterday: "Yesterday"]
    }
}

struct FeedingSummaryEntity: TransientAppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Feeding summary" }
    @Property(title: "Child") var childName: String
    @Property(title: "Period") var period: String
    @Property(title: "Breast milk, mL") var milkML: Double
    @Property(title: "Formula, mL") var formulaML: Double
    @Property(title: "Unrecorded milk/formula split, mL") var unknownML: Double
    @Property(title: "Total bottle intake, mL") var totalML: Double
    @Property(title: "Bottle feeds") var bottleCount: Int
    @Property(title: "Breastfeeding minutes") var nursingMinutes: Double
    @Property(title: "Breastfeeding sessions") var nursingCount: Int
    @Property(title: "As of") var asOf: Date
    var displayRepresentation: DisplayRepresentation { .init(title: "\(childName)’s feeding", subtitle: "\(period)") }
    init() {
        childName = ""; period = ""; milkML = 0; formulaML = 0; unknownML = 0; totalML = 0
        bottleCount = 0; nursingMinutes = 0; nursingCount = 0; asOf = .now
    }
    init(report: FeedingReport) {
        self.init()
        childName = report.childName; period = report.period.title
        milkML = report.summary.milkML.double; formulaML = report.summary.formulaML.double
        totalML = report.summary.totalML.double; bottleCount = report.summary.bottles
        unknownML = report.summary.unknownML.double
        nursingMinutes = report.summary.nursingSeconds / 60; nursingCount = report.summary.nursingSessions
        asOf = report.asOf
    }
}

struct GetFeedingIntakeIntent: AppIntent {
    static var title: LocalizedStringResource { "How much did my baby eat?" }
    static var description: IntentDescription { "Get recorded breast milk, formula, total bottle intake, and separate breastfeeding time for a child." }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Child") var child: ChildEntity?
    @Parameter(title: "Period", default: .last24Hours) var period: ReportPeriod
    @Parameter(title: "Volume unit") var unit: VolumeUnit?
    static var parameterSummary: some ParameterSummary { Summary("Get feeding totals for \(\.$period)") { \.$child; \.$unit } }
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<FeedingSummaryEntity> & ProvidesDialog & ShowsSnippetView {
        let now = Date.now
        let target = try await IntentResolution.child(child, parameter: $child)
        let store = LogStore.shared
        let report = FeedingReport(child: target, period: period, snapshot: store.snapshot, now: now)
        let unit = unit ?? store.volumeUnit
        return .result(value: FeedingSummaryEntity(report: report), dialog: IntentDialog(stringLiteral: report.spoken(unit: unit)), view: FeedingSummarySnippet(report: report, unit: unit))
    }
}

struct GetLastFeedIntent: AppIntent {
    static var title: LocalizedStringResource { "When was the last feed?" }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Child") var child: ChildEntity?
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let now = Date.now
        let target = try await IntentResolution.child(child, parameter: $child)
        let store = LogStore.shared
        let last = store.snapshot.activities.first { $0.childID == target.id && $0.occurredAt <= now && $0.payload.isComplete && [.bottle, .breastfeeding].contains($0.payload.kind) }
        let answer: String
        if let last { answer = "\(target.name)’s last recorded \(last.payload.kind.title.lowercased()) was \(last.occurredAt.formatted(date: .abbreviated, time: .shortened)): \(last.detail(unit: store.volumeUnit))." }
        else { answer = "No completed feeds have been recorded for \(target.name) yet." }
        return .result(value: answer, dialog: IntentDialog(stringLiteral: answer))
    }
}

struct FeedingSummarySnippet: View {
    let report: FeedingReport
    let unit: VolumeUnit
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(report.childName) · \(report.period.title)").font(.headline)
            Text(unit.quantity(report.summary.totalML)).font(.largeTitle.bold()).monospacedDigit()
            Text("Recorded bottle intake").font(.subheadline).foregroundStyle(.secondary)
            LabeledContent("Breast milk", value: unit.quantity(report.summary.milkML))
            LabeledContent("Formula", value: unit.quantity(report.summary.formulaML))
            if report.summary.unknownML > 0 { LabeledContent("Split not recorded", value: unit.quantity(report.summary.unknownML)) }
            if report.summary.nursingSessions > 0 {
                LabeledContent("Breastfeeding", value: LogAnalytics.duration(report.summary.nursingSeconds))
            }
            Text("Recorded entries as of \(report.asOf.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
        }.padding().privacySensitive()
    }
}
