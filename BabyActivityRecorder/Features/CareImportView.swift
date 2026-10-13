import SwiftUI

private struct CareImportPlan: Identifiable {
    let id = UUID()
    enum Target {
        case child(ChildProfile, [CareImportDraft])
        case pumping(Caregiver, [PumpImportDraft])
    }
    let target: Target
}

private struct CareImportSelection {
    // A concrete State value keeps initializer seeds separate from optional nil defaults.
    var childID: UUID?
    var motherID: UUID?
}

struct CareImportView: View {
    let store: LogStore
    private let pumpingContext: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selection: CareImportSelection
    @State private var addingProfile = false
    @State private var text = ""
    @State private var firstDay = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
    @State private var defaultUnit: VolumeUnit
    @State private var preparing = false
    @State private var error: String?
    @State private var plan: CareImportPlan?
    @State private var work: Task<Void, Never>?
    @FocusState private var editingText: Bool
    init(store: LogStore, pumpingProfile: Caregiver? = nil) {
        self.store = store; pumpingContext = pumpingProfile != nil
        defaultUnit = store.volumeUnit
        let profiles = store.snapshot.caregivers.filter(\.isMother)
        selection = CareImportSelection(childID: store.selectedChild?.id, motherID: pumpingProfile?.id ?? (profiles.count == 1 ? profiles.first?.id : nil))
    }
    private var pumping: Bool { pumpingContext || JSONLinesPumpImport.recognizes(text) }
    private var timeZone: TimeZone { TimeZone(identifier: store.snapshot.family?.timeZoneIdentifier ?? "") ?? .current }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("A handoff, without the retyping.").font(.title2.bold())
                    Text(pumping ? String(localized: "Paste pumping sessions as JSON Lines. Choose whose sessions these are, then review and save them together.") : String(localized: "Paste a handoff, feeding log, or pumping JSON Lines. Review the entries, then save them together.")).foregroundStyle(.secondary)
                    if pumping {
                        Picker("Pumping profile", selection: $selection.motherID) {
                            Text("Choose a caregiver").tag(nil as UUID?)
                            ForEach(store.snapshot.caregivers.filter(\.isMother)) { person in Text(person.name).tag(Optional(person.id)) }
                        }
                        Button("Add pumping profile", systemImage: "person.badge.plus") { addingProfile = true }
                        Text("All sessions go to this caregiver. Pumped milk is separate from the baby’s intake.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ChildPicker(children: store.snapshot.children, selectedID: selection.childID) { selection.childID = $0 }
                        LogDatePicker(title: String(localized: "First date in these notes"), selection: $firstDay, displayedComponents: .date)
                        Text("Undated notes start here. Dates and time zones written in your report take priority; otherwise times use \(timeZone.identifier).").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Care notes").font(.headline)
                        Spacer()
                        PasteButton(payloadType: String.self) { values in text = values.joined(separator: "\n") }
                            .labelStyle(.iconOnly).controlSize(.regular)
                    }
                    TextEditor(text: $text).focused($editingText).frame(height: 260)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .scrollContentBackground(.hidden).padding(12).background(LogStyle.card, in: .rect(cornerRadius: 20))
                        .accessibilityLabel("Paste or type care notes").accessibilityIdentifier("import.notes")
                    HStack {
                        Button("Try an example") { text = pumping ? JSONLinesPumpImport.example : CareNoteParser.sample }
                        Spacer()
                        Text("\(text.count.formatted())/\(CareNoteParser.maximumCharacters.formatted())").font(.caption).foregroundStyle(text.count > CareNoteParser.maximumCharacters ? .red : .secondary)
                    }
                    DisclosureGroup("Format tips & missing units") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("One activity per line works best. Use times such as 11:28 pm or 23:28, and amounts such as 2½ oz or 130 mL. BM means breast milk.")
                            Text("Optional date headings: 2026-09-18. Untimed entries and missing units are flagged for review.")
                            Text("Feeding exports also work: date and time | BM, Formula, or Mixed BM/formula | total | notes. Mixed components can use different units. Unknown splits stay separate from milk and formula totals.")
                            VolumePicker(unit: $defaultUnit)
                            Text("Missing units use a consistent unit from the report, or this choice if the report is mixed.").font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup("Advanced: JSON Lines") {
                                JSONLinesFormatGuide().padding(.top, 10)
                            }.accessibilityIdentifier("import.jsonlTips")
                        }.font(.subheadline).padding(.top, 10)
                    }
                    Text("Interpreted on this device. Nothing is saved until you review. Saved entries join your shared family log.").font(.footnote).foregroundStyle(.secondary)
                }.padding(22)
            }.background(LogStyle.canvas).scrollDismissesKeyboard(.interactively)
                .navigationTitle(pumping ? String(localized: "Import pumping") : String(localized: "Paste care notes")).navigationBarTitleDisplayMode(.inline)
                .environment(\.timeZone, timeZone)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { work?.cancel(); dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    EditorActionBar(editing: editingText, done: { editingText = false }) {
                        PrimaryButton(title: preparing ? String(localized: "Preparing your review…") : String(localized: "Review entries"), disabled: preparing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > CareNoteParser.maximumCharacters || !store.canEdit) { prepare() }
                    }
                }
                .sheet(item: $plan) { plan in
                    switch plan.target {
                    case .child(let child, let rows):
                        CareImportReviewView(store: store, child: child, rows: rows) { self.plan = nil; dismiss() }
                    case .pumping(let mother, let rows):
                        PumpImportReviewView(store: store, mother: mother, rows: rows) { self.plan = nil; dismiss() }
                    }
                }
                .sheet(isPresented: $addingProfile, onDismiss: {
                    let profiles = store.snapshot.caregivers.filter(\.isMother)
                    if profiles.count == 1 { selection.motherID = profiles[0].id }
                }) { CaregiverEditor(store: store, existing: nil) }
                .alert("Check care notes", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("OK", role: .cancel) {}
                } message: { Text(error ?? "") }
                .onDisappear { work?.cancel() }
        }.babyPalette(for: pumping ? nil : store.snapshot.children.first { $0.id == selection.childID }?.paletteGender)
    }
    private func prepare() {
        editingText = false; error = nil
        let isPumping = pumping
        let child = store.snapshot.children.first { $0.id == selection.childID }
        let mother = store.snapshot.caregivers.first { $0.id == selection.motherID && $0.isMother }
        if isPumping, mother == nil { error = String(localized: "Choose a pumping profile first."); return }
        if !isPumping, child == nil { error = String(localized: "Choose a child first."); return }
        let source = text, date = firstDay, unit = defaultUnit, zone = timeZone
        preparing = true
        work = Task {
            defer { preparing = false }
            do {
                if isPumping, let mother {
                    let parsed = try await Task.detached(priority: .userInitiated) { try JSONLinesPumpImport.parse(source) }.value
                    try Task.checkCancellation()
                    let rows = PumpImportDraft.excludingDuplicates(parsed, existing: store.snapshot.pumps, mother: mother, authorID: store.caregiverID)
                    plan = CareImportPlan(target: .pumping(mother, rows))
                } else if let child {
                    let parsed = try await CareNoteInterpreter.interpret(source, firstDay: date, timeZone: zone, defaultUnit: unit)
                    try Task.checkCancellation()
                    let rows = CareImportDraft.excludingDuplicates(parsed, existing: store.snapshot.activities, child: child, authorID: store.caregiverID)
                    plan = CareImportPlan(target: .child(child, rows))
                }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct CareImportReviewView: View {
    let store: LogStore
    let child: ChildProfile
    let saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [CareImportDraft]
    @State private var checked = false
    @State private var error: String?
    @State private var showOnlyIssues = false
    @State private var filteredIDs: Set<UUID> = []
    init(store: LogStore, child: ChildProfile, rows: [CareImportDraft], saved: @escaping () -> Void) {
        self.store = store; self.child = child; self.rows = rows; self.saved = saved
    }
    private var selected: [CareImportDraft] { rows.filter(\.included) }
    private var counts: String {
        CareImportKind.allCases.compactMap { kind -> String? in
            let count = selected.filter { $0.kind == kind }.count
            guard count > 0 else { return nil }
            switch kind {
            case .bottle: return String(localized: "\(count) bottles")
            case .diaper: return String(localized: "\(count) diapers")
            case .note: return String(localized: "\(count) notes")
            }
        }.joined(separator: " · ")
    }
    private var valid: Bool { !selected.isEmpty && selected.allSatisfy { (try? $0.activity(child: child, authorID: store.caregiverID)) != nil } }
    private var issueIDs: Set<UUID> { Set(selected.filter { validationIssue($0) != nil }.map(\.id)) }
    private var visibleRows: Binding<[CareImportDraft]> {
        // Keep edited rows visible until the filter is dismissed, even after their issue is fixed.
        Binding(get: { showOnlyIssues ? rows.filter { filteredIDs.contains($0.id) } : rows }, set: { changed in
            let updates = Dictionary(uniqueKeysWithValues: changed.map { ($0.id, $0) })
            rows = rows.map { updates[$0.id] ?? $0 }
        })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                    Label(child.name, systemImage: "person.crop.circle").font(.headline)
                    if !counts.isEmpty { Text(counts) }
                    if selected.isEmpty { Text("No entries selected. Similar entries start deselected.").font(.subheadline).foregroundStyle(.secondary) }
                    ImportReviewSummary(rows: selected, child: child, authorID: store.caregiverID)
                    Text("Original notes are kept with every entry.").font(.footnote).foregroundStyle(.secondary)
                    if !issueIDs.isEmpty || showOnlyIssues {
                        Toggle("Show only entries needing details (\(issueIDs.count))", isOn: $showOnlyIssues).font(.subheadline)
                    }
                    }
                }
                ForEach(visibleRows) { $row in Section { ImportDraftRow(row: $row, validationIssue: validationIssue(row)) } }
                Section {
                    if let error { ErrorNotice(message: error) }
                } footer: { Text("Imports keep the original wording and do not change your usual bottle amounts.") }
            }.scrollContentBackground(.hidden).background(LogStyle.canvas)
                .navigationTitle("Review \(rows.count) entries").navigationBarTitleDisplayMode(.inline)
                .environment(\.timeZone, TimeZone(identifier: store.snapshot.family?.timeZoneIdentifier ?? "") ?? .current)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                    if !issueIDs.isEmpty { Text("\(issueIDs.count) entries need details before saving.").font(.footnote).foregroundStyle(.secondary) }
                    Toggle("I checked the child, dates, and amounts", isOn: $checked).font(.subheadline)
                        .accessibilityIdentifier("import.confirm")
                    PrimaryButton(title: String(localized: "Save \(selected.count) entries"), disabled: !checked || !valid || !store.canEdit) {
                        do {
                            let entries = try selected.map { try $0.activity(child: child, authorID: store.caregiverID) }
                            let count = try store.importActivities(entries)
                            store.toast = String(localized: "\(count) entries imported for \(child.name)")
                            saved()
                        } catch { self.error = error.localizedDescription }
                    }.accessibilityLabel("Save \(selected.count) entries for \(child.name)")
                    }.padding().background(.bar)
                }
                .onChange(of: rows) { checked = false }
                .onChange(of: showOnlyIssues) { if showOnlyIssues { filteredIDs = issueIDs } }
        }.babyPalette(for: child.paletteGender)
    }
    private func validationIssue(_ row: CareImportDraft) -> String? {
        guard row.included else { return nil }
        do { _ = try row.activity(child: child, authorID: store.caregiverID); return nil }
        catch { return error.localizedDescription }
    }
}

private struct ImportReviewSummary: View {
    let rows: [CareImportDraft]
    let child: ChildProfile
    let authorID: UUID
    var body: some View {
        let entries = rows.compactMap { try? $0.activity(child: child, authorID: authorID) }
        let summary = ActivitySummary(activities: entries, childID: child.id)
        if summary.bottles > 0 {
            Text("\(VolumeUnit.ml.quantity(summary.totalML)) bottle intake").font(.headline).monospacedDigit()
            if summary.unknownML > 0 {
                Text("\(VolumeUnit.ml.quantity(summary.unknownML)) · Split not recorded").font(.footnote).foregroundStyle(.secondary)
                Text("Family devices need this update.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        if let first = rows.compactMap(\.timestamp).min(), let last = rows.compactMap(\.timestamp).max() {
            let zone = TimeZone(identifier: rows.first?.timeZoneIdentifier ?? "") ?? .current
            Text(dateRange(first, last, zone: zone))
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Times in \(zone.identifier)").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func dateRange(_ first: Date, _ last: Date, zone: TimeZone) -> String {
        var format = Date.FormatStyle(date: .abbreviated, time: .omitted)
        format.timeZone = zone
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        if calendar.isDate(first, inSameDayAs: last) { return first.formatted(format) }
        return "\(first.formatted(format)) – \(last.formatted(format))"
    }
}

private struct ImportDraftRow: View {
    @Binding var row: CareImportDraft
    var validationIssue: String?
    @State private var missingTime = Date.now
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
        Toggle(isOn: $row.included) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                if let date = row.timestamp { Text(date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.subheadline).foregroundStyle(.secondary) }
                else { Text("Time needed").font(.subheadline).foregroundStyle(.orange) }
            }
        }.disabled(row.importIssue != nil)
        ForEach(row.reviewReasons, id: \.self) { reason in Label(reason, systemImage: "pencil.circle").font(.caption).foregroundStyle(.secondary) }
        if let validationIssue { Label(validationIssue, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
        DisclosureGroup("Original note") {
            Text(row.source).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
        }.font(.subheadline)
        DisclosureGroup("Edit details") {
            Picker("Activity", selection: $row.kind) { ForEach(CareImportKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
            if row.timestamp != nil {
                LogDatePicker(title: String(localized: "When"), selection: Binding(get: { row.timestamp ?? .now }, set: { row.timestamp = $0 }))
            } else {
                LogDatePicker(title: String(localized: "Choose a time"), selection: $missingTime)
                Button("Use this time") { row.timestamp = missingTime }
            }
            switch row.kind {
            case .bottle:
                VolumePicker(unit: Binding(get: { row.unit }, set: { row.changeUnit($0) }))
                Toggle("Split not recorded", isOn: Binding(get: { !row.unknown.isEmpty }, set: { row.setSplitUnknown($0) }))
                if !row.unknown.isEmpty {
                    amountField("Total", value: $row.unknown)
                    Text("Included in total intake. No milk or formula amount is guessed.").font(.caption).foregroundStyle(.secondary)
                } else {
                    amountField("Milk", value: $row.milk)
                    amountField("Formula", value: $row.formula)
                }
                if row.amountIssue != nil {
                    Button("Use the amounts entered above") { row.amountIssue = nil }
                }
            case .diaper:
                Toggle("Pee", isOn: $row.pee); Toggle("Poo", isOn: $row.poo)
            case .note: TextField("Care note", text: $row.note, axis: .vertical).lineLimit(3...10)
            }
        }
        }.buttonStyle(.borderless).padding(.vertical, 6)
            .environment(\.timeZone, TimeZone(identifier: row.timeZoneIdentifier ?? "") ?? .current)
    }
    private func amountField(_ title: String, value: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("0", text: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; row.amountIssue = nil }))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel(title)
        }
    }
    private var title: String {
        switch row.kind {
        case .bottle:
            if !row.unknown.isEmpty { return String(localized: "\(display(row.unknown)) \(row.unit.label) · Split not recorded") }
            let parts = [(row.milk, String(localized: "milk")), (row.formula, String(localized: "formula"))].filter { !$0.0.isEmpty && $0.0 != "0" }.map { "\(display($0.0)) \(row.unit.label) \($0.1)" }
            return parts.isEmpty ? String(localized: "Bottle · Amount needed") : parts.joined(separator: " + ")
        case .diaper: return Diaper(pee: row.pee, poo: row.poo).title
        case .note: return String(localized: "Care note")
        }
    }
    private func display(_ value: String) -> String {
        Decimal.input(value).map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? value
    }
}
