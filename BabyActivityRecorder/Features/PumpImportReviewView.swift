import SwiftUI

struct PumpImportReviewView: View {
    let store: LogStore
    let mother: Caregiver
    let saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [PumpImportDraft]
    @State private var checked = false
    @State private var error: String?
    @FocusState private var editing: Bool

    init(store: LogStore, mother: Caregiver, rows: [PumpImportDraft], saved: @escaping () -> Void) {
        self.store = store; self.mother = mother; self.rows = rows; self.saved = saved
    }
    private var selected: [PumpImportDraft] { rows.filter(\.included) }
    private var valid: Bool { !selected.isEmpty && selected.allSatisfy { validationIssue($0) == nil } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(mother.name, systemImage: "person.crop.circle").font(.headline)
                        Text(selected.count == 1 ? String(localized: "1 pumping session") : String(localized: "\(selected.count) pumping sessions"))
                        let total = selected.compactMap { try? $0.session(mother: mother, authorID: store.caregiverID) }.reduce(Decimal.zero) { $0 + $1.totalML }
                        Text("\(VolumeUnit.ml.quantity(total)) pumped").font(.title3.bold()).monospacedDigit()
                        if let first = selected.map(\.occurredAt).min(), let last = selected.map(\.occurredAt).max() {
                            Text(dateRange(first, last)).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("Separate from bottle intake. Original notes and exact amounts are kept.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach($rows) { $row in
                    Section {
                        PumpImportRow(row: $row, issue: validationIssue(row)).focused($editing)
                    }
                }
                if let error { Section { ErrorNotice(message: error) } }
            }
            .scrollContentBackground(.hidden).background(LogStyle.canvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Review pumping").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                EditorActionBar(editing: editing, done: { editing = false }) {
                    VStack(alignment: .leading, spacing: 12) {
                        if !valid { Text(selected.isEmpty ? String(localized: "Select the sessions you want to import.") : String(localized: "Check the highlighted details before saving.")).font(.footnote).foregroundStyle(.secondary) }
                        Toggle("I checked the caregiver, dates, and amounts", isOn: $checked).font(.subheadline)
                            .accessibilityIdentifier("import.pumping.confirm")
                        PrimaryButton(title: selected.count == 1 ? String(localized: "Save 1 session") : String(localized: "Save \(selected.count) sessions"), disabled: !checked || !valid || !store.canEdit) { save() }
                            .accessibilityLabel("Save \(selected.count) pumping sessions for \(mother.name)")
                    }
                }
            }
            .onChange(of: rows) { checked = false }
        }.tint(LogStyle.forest)
    }

    private func dateRange(_ first: Date, _ last: Date) -> String {
        var format = Date.FormatStyle(date: .abbreviated, time: .omitted)
        format.timeZone = TimeZone(identifier: rows.first?.timeZoneIdentifier ?? "") ?? .current
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = format.timeZone
        if calendar.isDate(first, inSameDayAs: last) { return first.formatted(format) }
        return "\(first.formatted(format)) – \(last.formatted(format))"
    }
    private func validationIssue(_ row: PumpImportDraft) -> String? {
        guard row.included else { return nil }
        do { _ = try row.session(mother: mother, authorID: store.caregiverID); return nil }
        catch { return error.localizedDescription }
    }
    private func save() {
        do {
            let entries = try selected.map { try $0.session(mother: mother, authorID: store.caregiverID) }
            let count = try store.importPumpingSessions(entries)
            store.toast = String(localized: "\(count) pumping sessions imported for \(mother.name)")
            saved()
        } catch { self.error = error.localizedDescription }
    }
}

private struct PumpImportRow: View {
    @Binding var row: PumpImportDraft
    let issue: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $row.included) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(display(row.total)) mL pumped").font(.headline).monospacedDigit()
                    Text(row.occurredAt, format: .dateTime.year().month(.abbreviated).day().hour().minute())
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(row.timeZoneIdentifier).font(.caption).foregroundStyle(.secondary)
                }
            }.disabled(row.duplicateIdentity)
            if let reason = row.reviewReason { Label(reason, systemImage: "doc.on.doc").font(.caption).foregroundStyle(.secondary) }
            if let issue { Label(issue, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
            if row.left.isEmpty && row.right.isEmpty { Text("Left/right split not recorded").font(.caption).foregroundStyle(.secondary) }
            else { Text("Left \(display(row.left)) mL · Right \(display(row.right)) mL").font(.subheadline) }
            if !row.duration.isEmpty { Text("\(display(row.duration)) minutes").font(.subheadline).foregroundStyle(.secondary) }
            if !row.notes.isEmpty { Text(row.notes).font(.subheadline) }
            DisclosureGroup("Edit details") {
                LogDatePicker(title: String(localized: "When"), selection: $row.occurredAt)
                amount(String(localized: "Total (mL)"), value: $row.total)
                amount(String(localized: "Left (mL)"), value: $row.left)
                amount(String(localized: "Right (mL)"), value: $row.right)
                Text("Leave both sides blank when the split is unknown.").font(.caption).foregroundStyle(.secondary)
                amount(String(localized: "Duration (minutes)"), value: $row.duration)
                TextField("Notes", text: $row.notes, axis: .vertical).lineLimit(2...8)
            }.disabled(row.duplicateIdentity)
            DisclosureGroup("Original JSON · Line \(row.sourceLine)") {
                Text(row.sourceJSON).font(.footnote.monospaced()).textSelection(.enabled)
            }.font(.subheadline)
        }.padding(.vertical, 6).buttonStyle(.borderless)
            .environment(\.timeZone, TimeZone(identifier: row.timeZoneIdentifier) ?? .current)
    }
    private func amount(_ title: String, value: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("Optional", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityLabel(title)
        }
    }
    private func display(_ value: String) -> String {
        Decimal.input(value).map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? value
    }
}

#if DEBUG
#Preview("Review pumping import") {
    @Previewable @State var store = PreviewData.makeStore()
    let mother = store.snapshot.caregivers.first { $0.isMother }!
    let rows = try! JSONLinesPumpImport.parse(JSONLinesPumpImport.example.replacingOccurrences(of: #""totalML":105"#, with: #""totalML":null"#) + "\n" + JSONLinesPumpImport.totalOnlyExample)
    PumpImportReviewView(store: store, mother: mother, rows: rows) {}
}

#Preview("Paste pumping JSONL") {
    @Previewable @State var store = PreviewData.makeStore()
    CareImportView(store: store, pumpingProfile: store.snapshot.caregivers.first { $0.isMother })
}

#Preview("Edit imported pumping") {
    @Previewable @State var store = PreviewData.makeStore()
    let mother = store.snapshot.caregivers.first { $0.isMother }!
    let row = try! JSONLinesPumpImport.parse(JSONLinesPumpImport.totalOnlyExample)[0]
    PumpEditor(store: store, existing: try! row.session(mother: mother, authorID: store.caregiverID))
}
#endif
