import SwiftUI

struct RecoveryView: View {
    let store: LogStore
    private var records: [ProjectedRecord] {
        store.snapshot.records.filter { $0.isDeleted || $0.hasConflict }.sorted { $0.revision.date > $1.revision.date }
    }
    var body: some View {
        List {
            Section {
                if records.isEmpty {
                    ContentUnavailableView("All caught up", systemImage: "checkmark.circle", description: Text("Deleted entries and competing edits will appear here."))
                }
                ForEach(records) { record in
                    NavigationLink {
                        RecordRecoveryView(store: store, record: record)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.revision.value.recoveryTitle(in: store.snapshot)).font(.headline)
                            Text(
                                record.hasConflict
                                    ? String(localized: "Competing edits")
                                    : record.revision.value.mergedCaregiver != nil
                                        ? String(localized: "Merged profile") : String(localized: "Deleted")
                            ).font(.subheadline).foregroundStyle(.secondary)
                            Text(record.revision.date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                }
            } footer: {
                Text("Choose a version to keep. Earlier versions stay in history. Restore a deleted child before restoring individual entries for that child.")
            }
        }.navigationTitle("Review & restore")
            .scrollContentBackground(.hidden).background(LogStyle.canvas)
    }
}

private struct RecordRecoveryView: View {
    let store: LogStore
    let record: ProjectedRecord
    @Environment(\.dismiss) private var dismiss
    @State private var selected: RecordRevision?
    @State private var confirmation = false
    @State private var error: String?
    @State private var separating: Caregiver?
    private var isCaregiver: Bool {
        if case .caregiver = record.revision.value { return true }
        return false
    }
    var body: some View {
        List {
            Section {
                Text(record.revision.value.recoveryTitle(in: store.snapshot)).font(.title2.bold())
                Text(
                    record.revision.value.mergedCaregiver != nil
                        ? String(localized: "This duplicate was combined with another caregiver. Original records and authorship are still kept.")
                        : record.isDeleted
                            ? String(localized: "Restoring makes this record visible to the family again.")
                            : String(localized: "Select the complete version you want to keep. Amounts won’t be combined.")
                )
                    .foregroundStyle(.secondary)
                if isCaregiver, record.isDeleted, !store.isOwner {
                    Text("Only the family owner can restore a caregiver profile.").foregroundStyle(.secondary)
                }
            }
            if let person = record.revision.value.mergedCaregiver,
                let destinationID = person.mergedIntoID,
                record.isDeleted, !record.hasConflict
            {
                Section {
                    LabeledContent(
                        "Combined with", value: store.snapshot.caregiverName(destinationID))
                    Button("Separate profiles", systemImage: "person.2") { separating = person }
                        .disabled(!store.isOwner || !store.canEdit)
                        .accessibilityIdentifier("caregiver.merge.separate")
                } footer: {
                    Text(
                        "Original sessions return to their original profiles. Entries added after the merge stay with the kept profile. The restored profile has no Apple Account or invitation attached."
                    )
                }
            }
            if let error { Section { ErrorNotice(message: error) } }
            Section("Saved versions") {
                ForEach(store.history(for: record.id)) { revision in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            revision.value.mergedCaregiver != nil
                                ? String(localized: "Profiles merged")
                                : revision.deleted
                                    ? String(localized: "Deleted")
                                    : revision.value.recoveryDetail(unit: store.volumeUnit)
                        ).font(.headline)
                        Text("\(store.snapshot.caregiverName(revision.editorID)) · \(revision.date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                        if record.heads.contains(where: { $0.id == revision.id }) { Text("Current version").font(.caption).foregroundStyle(LogStyle.forest) }
                        if store.canEdit && revision.value.mergedCaregiver == nil
                            && (record.revision.value.mergedCaregiver == nil || record.hasConflict)
                            && (!isCaregiver || (!record.isDeleted && !revision.deleted)
                                || store.isOwner)
                        {
                            Button(revision.deleted ? String(localized: "Keep deletion") : record.isDeleted ? String(localized: "Restore this version") : String(localized: "Use this version")) {
                                selected = revision; confirmation = true
                            }.frame(minHeight: 44)
                        }
                    }.padding(.vertical, 6)
                }
            }
        }.navigationTitle("Change history").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(selected?.deleted == true ? String(localized: "Keep this record deleted?") : record.isDeleted ? String(localized: "Restore this version?") : String(localized: "Use this version?"), isPresented: $confirmation, titleVisibility: .visible) {
                Button("Confirm") {
                    guard let selected else { return }
                    do { try store.resolve(record, using: selected); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            } message: { Text("This change is shared with the family. Every previous version is retained.") }
            .confirmationDialog(
                "Separate these profiles?", item: $separating, titleVisibility: .visible
            ) { person in
                Button("Separate profiles") {
                    do { try store.separateCaregiver(person.id); dismiss() } catch {
                        self.error = error.localizedDescription
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text(
                    "Restore the duplicate as an unlinked profile and return its original history. Newer entries stay with the kept profile. This change syncs to your family."
                )
            }
    }
}

private extension RecordValue {
    var mergedCaregiver: Caregiver? {
        if case .caregiver(let person) = self, person.mergedIntoID != nil { return person }
        return nil
    }
    func recoveryTitle(in snapshot: FamilySnapshot) -> String {
        switch self {
        case .child(let child): String(localized: "Child · \(child.name)")
        case .caregiver(let person): String(localized: "Caregiver · \(person.name)")
        case .activity(let activity): String(localized: "\(activity.payload.kind.title) · \(snapshot.children.first { $0.id == activity.childID }?.name ?? String(localized: "Deleted child"))")
        case .pumping(let session): String(localized: "Pumping · \(snapshot.caregiverName(session.motherID))")
        case .milestone(let observation): String(localized: "Milestone · \(observation.skillTitle)")
        }
    }
    func recoveryDetail(unit: VolumeUnit) -> String {
        switch self {
        case .child(let child): child.name
        case .caregiver(let person): person.name
        case .activity(let activity): "\(activity.detail(unit: unit))\n\(activity.occurredAt.formatted(date: .abbreviated, time: .shortened))\(activity.note.isEmpty ? "" : "\n\(activity.note)")"
        case .pumping(let pump): String(localized: "\(unit.quantity(pump.totalML)) pumped\n\(pump.occurredAt.formatted(date: .abbreviated, time: .shortened))")
        case .milestone(let observation): "\(observation.status.title) · \(observation.recordedAt.formatted(date: .abbreviated, time: .omitted))\n\(observation.note)"
        }
    }
}
