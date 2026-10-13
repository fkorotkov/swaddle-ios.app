#if DEBUG
import SwiftUI

@MainActor
enum PreviewData {
    static func pumpingHelperStore(profiles: Int = 1) -> LogStore {
        let store = LogStore(
            persistence: PersistenceController(inMemory: true), defaults: UserDefaults(suiteName: "preview.\(UUID())")!,
            publishesWidgets: false)
        do {
            try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml)
            guard let family = store.snapshot.family else { return store }
            for name in ["Alex", "Jamie"].prefix(profiles) {
                let person = Caregiver(familyID: family.id, name: name, isMother: true)
                try store.save(.caregiver(person))
                try store.save(
                    .pumping(
                        PumpSession(
                            familyID: family.id, motherID: person.id,
                            occurredAt: .now.addingTimeInterval(-3600), authorID: person.id,
                            totalML: 105, unit: .ml)))
            }
        } catch { assertionFailure("Pumping helper preview failed: \(error)") }
        return store
    }

    static func pumpingTrendsStore(profiles: Int = 1, hasSessions: Bool = true) -> LogStore {
        let store = LogStore(persistence: PersistenceController(inMemory: true), defaults: UserDefaults(suiteName: "preview.\(UUID())")!, publishesWidgets: false)
        do {
            try store.createFamily(childName: "Robin", caregiverName: "Alex", mother: profiles > 0, unit: .ml)
            guard let family = store.snapshot.family else { return store }
            if profiles > 1 { try store.save(.caregiver(Caregiver(familyID: family.id, name: "Sam", isMother: true))) }
            if profiles > 0 && hasSessions {
                for day in 0..<7 where day != 3 {
                    for session in 0..<3 {
                        try store.save(.pumping(PumpSession(familyID: family.id, motherID: store.caregiverID,
                            occurredAt: .now.addingTimeInterval(-Double(day * 86400 + session * 7200 + 600)),
                            authorID: store.caregiverID, totalML: Decimal(75 + day * 5 + session * 15), unit: .ml)))
                    }
                }
            }
        } catch { assertionFailure("Pumping trends preview failed: \(error)") }
        return store
    }
    static func siriStore() -> LogStore {
        let store = makeStore()
        do {
            try store.setSiriDiscoveryEnabled(true)
            if let child = store.selectedChild {
                try store.save(.activity(Activity(familyID: child.familyID, childID: child.id, occurredAt: .now.addingTimeInterval(-1800), authorID: store.caregiverID, note: "Evening observation\nRobin settled after feeding and a cuddle.", payload: .careNote)))
            }
        } catch { assertionFailure("Siri preview failed: \(error)") }
        return store
    }
    static func invitationStore() -> LogStore {
        let store = makeStore()
        if let family = store.snapshot.family {
            do { try store.save(.caregiver(Caregiver(familyID: family.id, name: "Alex", isMother: true))) }
            catch { assertionFailure("Invitation preview failed: \(error)") }
        }
        return store
    }
    static func recoveryStore() -> LogStore {
        let store = makeStore(twins: true)
        do {
            if var bottle = store.snapshot.activities.first(where: { $0.payload.kind == .bottle }),
               let original = store.snapshot.record(bottle.id) {
                let parents = Set(original.heads.map(\.id))
                bottle.payload = .bottle(Bottle(milkML: 90, formulaML: 0, unit: .ml))
                try store.save(.activity(bottle), parentIDs: parents)
                bottle.payload = .bottle(Bottle(milkML: 120, formulaML: 30, unit: .ml))
                try store.save(.activity(bottle), parentIDs: parents)
            }
            if let diaper = store.snapshot.activities.first(where: { $0.payload.kind == .diaper }), let record = store.snapshot.record(diaper.id) {
                try store.delete(record)
            }
        } catch { assertionFailure("Preview recovery failed: \(error)") }
        return store
    }
    static func bottleStore(gender: ChildGender? = nil, unit: VolumeUnit = .ml) -> LogStore {
        let store = makeStore(gender: gender)
        if let child = store.selectedChild {
            do {
                try store.save(.activity(Activity(familyID: child.familyID, childID: child.id, occurredAt: .now, authorID: store.caregiverID, payload: .bottle(Bottle(milkML: unit == .ml ? 90 : unit.toML(3), formulaML: unit == .ml ? 30 : unit.toML(1), unit: unit)))), rememberBottle: true)
            } catch { assertionFailure("Preview bottle failed: \(error)") }
        }
        return store
    }
    static func makeStore(twins: Bool = false, gender: ChildGender? = nil, childName: String = "Robin") -> LogStore {
        let store = LogStore(persistence: PersistenceController(inMemory: true), defaults: UserDefaults(suiteName: "preview.\(UUID())")!, publishesWidgets: false)
        do {
            try store.createFamily(childName: childName, caregiverName: "Sam", mother: true, unit: .ml, gender: gender)
            guard let child = store.selectedChild else { return store }
            let now = Date.now
            for day in 0..<7 {
                for feed in 0..<5 {
                    let time = now.addingTimeInterval(-Double(day * 86400 + feed * 14400 + 2700))
                    try store.save(.activity(Activity(familyID: child.familyID, childID: child.id, occurredAt: time, authorID: store.caregiverID, payload: .bottle(Bottle(milkML: 80 + Decimal(feed * 5), formulaML: feed % 2 == 0 ? 30 : 40, unit: .ml)))))
                }
            }
            for index in 0..<8 {
                let diaper = Diaper(pee: index != 4, poo: index >= 4)
                try store.save(.activity(Activity(familyID: child.familyID, childID: child.id, occurredAt: now.addingTimeInterval(-Double(index * 9600 + 1200)), authorID: store.caregiverID, payload: .diaper(diaper))))
            }
            for (daysAgo, grams) in [(20, 3360), (16, 3290), (12, 3420), (7, 3600), (0, 3860)] {
                try store.save(.activity(Activity(familyID: child.familyID, childID: child.id, occurredAt: now.addingTimeInterval(-Double(daysAgo * 86400 + 3600)), authorID: store.caregiverID, payload: .weight(grams: Decimal(grams), unit: "kg"))))
            }
            try store.save(.pumping(PumpSession(familyID: child.familyID, motherID: store.caregiverID, occurredAt: now.addingTimeInterval(-7200), authorID: store.caregiverID, totalML: 105, leftML: 60, rightML: 45, unit: .ml)))
            if twins { try store.save(.child(ChildProfile(familyID: child.familyID, name: "Jamie"))) }
            store.selectedChildID = child.id
        } catch { assertionFailure("Preview fixture failed: \(error)") }
        return store
    }
}

#Preview("Today") {
    @Previewable @State var store = PreviewData.makeStore()
    ContentView(store: store).tint(LogStyle.forest)
}
#Preview("Today · Dark") {
    @Previewable @State var store = PreviewData.makeStore()
    ContentView(store: store).tint(LogStyle.forest).preferredColorScheme(.dark)
}
#Preview("Today · Accessibility") {
    @Previewable @State var store = PreviewData.makeStore()
    ContentView(store: store).tint(LogStyle.forest).environment(\.dynamicTypeSize, .accessibility3)
}
#Preview("Bottle") {
    @Previewable @State var store = PreviewData.makeStore()
    ActivityEditor(store: store, route: LogRoute(kind: .bottle, childID: store.selectedChild?.id)).tint(LogStyle.forest)
}
#Preview("Family · Twins") {
    @Previewable @State var store = PreviewData.makeStore(twins: true)
    SettingsView(store: store).tint(LogStyle.forest)
}
#Preview("Trends") {
    @Previewable @State var store = PreviewData.makeStore()
    TrendsView(store: store).tint(LogStyle.forest)
}
#Preview("Trends · Pumping") {
    @Previewable @State var store = PreviewData.pumpingTrendsStore(profiles: 2)
    TrendsView(store: store, initialMetric: .pumping).tint(LogStyle.forest)
}
#Preview("Trends · Pumping · Large dark") {
    @Previewable @State var store = PreviewData.pumpingTrendsStore()
    TrendsView(store: store, initialMetric: .pumping).tint(LogStyle.forest)
        .preferredColorScheme(.dark).environment(\.dynamicTypeSize, .accessibility3)
}
#Preview("Trends · Pumping · Empty") {
    @Previewable @State var store = PreviewData.pumpingTrendsStore(hasSessions: false)
    TrendsView(store: store, initialMetric: .pumping).tint(LogStyle.forest)
}
#Preview("Trends · Pumping · Add profile") {
    @Previewable @State var store = PreviewData.pumpingTrendsStore(profiles: 0)
    TrendsView(store: store, initialMetric: .pumping).tint(LogStyle.forest)
}
#Preview("Bottle · Previous amounts") {
    @Previewable @State var store = PreviewData.bottleStore()
    ActivityEditor(store: store, route: LogRoute(kind: .bottle, childID: store.selectedChild?.id)).tint(LogStyle.forest)
}
#Preview("Bottle · Dark") {
    @Previewable @State var store = PreviewData.bottleStore()
    ActivityEditor(store: store, route: LogRoute(kind: .bottle, childID: store.selectedChild?.id)).tint(LogStyle.forest).preferredColorScheme(.dark)
}
#Preview("Review & restore") {
    @Previewable @State var store = PreviewData.recoveryStore()
    NavigationStack { RecoveryView(store: store) }.tint(LogStyle.forest)
}
#Preview("Siri · Hands-free") {
    @Previewable @State var store = PreviewData.makeStore()
    NavigationStack { SiriSetupView(store: store, childName: "Robin") }.tint(LogStyle.forest)
}
#Preview("Paste care notes") {
    @Previewable @State var store = PreviewData.makeStore()
    CareImportView(store: store).tint(LogStyle.forest)
}
#Preview("Import · Review") {
    @Previewable @State var store = PreviewData.makeStore()
    if let child = store.selectedChild,
       let rows = try? CareNoteParser.parse(CareNoteParser.sample, firstDay: Date.now.addingTimeInterval(-86400), timeZone: .current, defaultUnit: .ml) {
        CareImportReviewView(store: store, child: child, rows: rows, saved: {}).tint(LogStyle.forest)
    }
}
#Preview("Siri · Feeding answer", traits: .sizeThatFitsLayout) {
    @Previewable @State var store = PreviewData.makeStore()
    if let child = store.selectedChild {
        FeedingSummarySnippet(report: FeedingReport(child: child, period: .last24Hours, snapshot: store.snapshot, now: .now), unit: .ml)
    }
}
#Preview("Today · Boy") {
    @Previewable @State var store = PreviewData.makeStore(gender: .boy)
    ContentView(store: store)
}
#Preview("Today · Girl") {
    @Previewable @State var store = PreviewData.makeStore(gender: .girl)
    ContentView(store: store)
}
#Preview("Today · Boy · Dark") {
    @Previewable @State var store = PreviewData.makeStore(gender: .boy)
    ContentView(store: store).preferredColorScheme(.dark)
}
#Preview("Today · Girl · Dark") {
    @Previewable @State var store = PreviewData.makeStore(gender: .girl)
    ContentView(store: store).preferredColorScheme(.dark)
}
#Preview("Today · Girl · Accessibility") {
    @Previewable @State var store = PreviewData.makeStore(gender: .girl)
    ContentView(store: store).environment(\.dynamicTypeSize, .accessibility3)
}
#Preview("Summary · Largest text", traits: .sizeThatFitsLayout) {
    @Previewable @State var store = PreviewData.makeStore(gender: .boy)
    SummaryCards(summary: ActivitySummary(activities: store.snapshot.activities, childID: store.selectedChildID, start: .now.addingTimeInterval(-86400)), unit: .ml)
        .padding(22).frame(width: 375).background(LogStyle.canvas)
        .babyPalette(for: .boy).environment(\.dynamicTypeSize, .accessibility5)
}
#Preview("History · Largest text", traits: .sizeThatFitsLayout) {
    @Previewable @State var store = PreviewData.makeStore()
    if let activity = store.snapshot.activities.first(where: { $0.payload.kind == .bottle }) {
        ActivityRow(activity: activity, author: "Alexandra Thompson", unit: .ml)
            .padding(22).frame(width: 375).background(LogStyle.canvas)
            .environment(\.dynamicTypeSize, .accessibility5)
    }
}
#Preview("Nursing clock · Largest text", traits: .sizeThatFitsLayout) {
    NursingClock(nursing: Nursing(caregiverID: UUID(), segments: [NursingSegment(side: .left, start: .now.addingTimeInterval(-900))]), now: .now)
        .padding(22).frame(width: 375).environment(\.dynamicTypeSize, .accessibility5)
}
#Preview("Bottle · Quick adjustments") {
    @Previewable @State var store = PreviewData.bottleStore(gender: .boy, unit: .oz)
    ActivityEditor(store: store, route: LogRoute(kind: .bottle, childID: store.selectedChild?.id))
}

#Preview("Pumping") {
    @Previewable @State var store = PreviewData.makeStore()
    PumpEditor(store: store, existing: nil)
}
#Preview("Today · Long name") {
    @Previewable @State var store = PreviewData.makeStore(twins: true, gender: .girl, childName: "Alexandra Beatrice")
    ContentView(store: store)
}
#Preview("Event time · Largest text", traits: .sizeThatFitsLayout) {
    @Previewable @State var date = Date.now
    EventTimeField(date: $date, quickMinutes: [0, 30, 45])
        .padding(22).frame(width: 375).background(LogStyle.canvas)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Today · Glass controls · Twins") {
    @Previewable @State var store = PreviewData.makeStore(twins: true, gender: .girl)
    ContentView(store: store)
}
#Preview("Bottle · Quick adjustments · Dark") {
    @Previewable @State var store = PreviewData.bottleStore(gender: .boy, unit: .oz)
    ActivityEditor(store: store, route: LogRoute(kind: .bottle, childID: store.selectedChild?.id))
        .preferredColorScheme(.dark)
}
#Preview("Confirmation · Largest text", traits: .sizeThatFitsLayout) {
    SaveConfirmation(message: "Bottle saved for Alexandra Beatrice", undoID: UUID(), undo: {}, dismiss: {})
        .padding(16).frame(width: 375).background(LogStyle.canvas)
        .environment(\.dynamicTypeSize, .accessibility5)
}

private struct StructuredImportPreview: View {
    @State private var store = PreviewData.makeStore()
    var body: some View {
        if let child = store.selectedChild,
           let rows = try? CareNoteParser.parse("""
           Timezone: America/New_York. BM = breast milk. All feeds are bottles.
           2026-05-10 08:00 | Mixed BM/formula | 64.15 ml | Breast milk 2 oz; formula 5 ml.
           2026-05-10 11:00 | Mixed BM/formula | 95 ml | Split not recorded.
           2026-05-10 14:00 | BM | 118.29 ml | Breast milk 4 oz. Original observation with another time at 14:20.
           """, firstDay: .now, timeZone: .current, defaultUnit: .ml) {
            CareImportReviewView(store: store, child: child, rows: rows, saved: {}).tint(LogStyle.forest)
        }
    }
}
#Preview("Import · Structured") { StructuredImportPreview() }
#Preview("Import · Structured dark") { StructuredImportPreview().preferredColorScheme(.dark) }
#Preview("Import · Structured large text") { StructuredImportPreview().environment(\.dynamicTypeSize, .accessibility3) }
#endif
