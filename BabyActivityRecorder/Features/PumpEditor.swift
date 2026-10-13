import SwiftUI

private struct PumpProfileSelection {
    var id: UUID?
}

#if DEBUG
#Preview("Pumping · Previous side volumes") {
    @Previewable @State var store = PreviewData.makeStore()
    PumpEditor(store: store, existing: nil)
}

#Preview("Pumping · Previous total · Large dark") {
    @Previewable @State var store = PreviewData.pumpingTrendsStore()
    PumpEditor(store: store, existing: nil)
        .preferredColorScheme(.dark).environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Pumping · Recorded by another caregiver") {
    @Previewable @State var store = PreviewData.pumpingHelperStore()
    PumpEditor(store: store, existing: nil)
}

#Preview("Pumping · Choose who pumped") {
    @Previewable @State var store = PreviewData.pumpingHelperStore(profiles: 2)
    PumpEditor(store: store, existing: nil)
        .preferredColorScheme(.dark).environment(\.dynamicTypeSize, .accessibility3)
}
#endif

struct PumpEditor: View {
    let store: LogStore
    let existing: PumpSession?
    @Environment(\.dismiss) private var dismiss
    @State private var volume: VolumeDraft
    @State private var split: Bool
    @State private var profile: PumpProfileSelection
    @State private var volumePreset: PumpVolumePreset?
    @State private var occurredAt: Date
    @State private var minutes: String
    @State private var note: String
    @State private var error: String?
    @State private var addingProfile = false
    @State private var confirmDelete = false
    @FocusState private var focusedField: ActivityEditorField?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let id: UUID
    private let commandID = UUID()
    private let parents: Set<UUID>
    private var pumpingProfiles: [Caregiver] { store.snapshot.caregivers.filter(\.isMother) }
    private var selectedProfile: Caregiver? { pumpingProfiles.first { $0.id == profile.id } }
    init(store: LogStore, existing: PumpSession?, initialMotherID: UUID? = nil) {
        self.store = store; self.existing = existing
        id = existing?.id ?? UUID()
        parents = Set(existing.flatMap { store.snapshot.record($0.id) }?.heads.map(\.id) ?? [])
        let mothers = store.snapshot.caregivers.filter(\.isMother)
        let selectedID =
            (existing?.motherID ?? initialMotherID).map { store.snapshot.canonicalCaregiverID($0) }
            ?? (mothers.count == 1 ? mothers.first?.id : nil)
        profile = PumpProfileSelection(id: mothers.contains { $0.id == selectedID } ? selectedID : nil)
        let preset = existing == nil ? PumpVolumePreset.latest(for: selectedID, in: store.snapshot) : nil
        volumePreset = preset
        // Seed this sheet's draft once; incoming iCloud updates must not replace edits.
        if let existing {
            volume = VolumeDraft(unit: existing.unit, firstML: existing.leftML ?? existing.totalML, secondML: existing.rightML)
            split = existing.leftML != nil
        } else {
            volume = preset?.draft(unit: store.volumeUnit) ?? VolumeDraft(unit: store.volumeUnit)
            split = preset?.split ?? false
        }
        occurredAt = existing?.occurredAt ?? .now; minutes = existing?.minutes?.formatted() ?? ""; note = existing?.note ?? ""
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: verticalSize == .compact ? 12 : 24) {
                    if !typeSize.isAccessibilitySize && verticalSize != .compact {
                        Text("A little set aside.").font(
                            .system(.title, design: .serif, weight: .semibold))
                    }
                    Text("Choose who pumped. Pumped milk is separate from each child’s intake.").foregroundStyle(LogStyle.muted)
                    pumpingProfileCard
                    VolumePicker(unit: Binding(get: { volume.unit }, set: { volume.changeUnit($0) }))
                    Picker("Pumping entry", selection: Binding(get: { split }, set: changeEntryMode)) {
                        Text("Total").tag(false)
                        Text(typeSize.isAccessibilitySize ? String(localized: "By side") : String(localized: "Left + right")).tag(true)
                    }.logPickerStyle()
                    if let volumePreset {
                        Label("Last session: \(volume.unit.quantity(volumePreset.session.totalML)) · \(volumePreset.session.occurredAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock.arrow.circlepath")
                            .font(.footnote).foregroundStyle(LogStyle.muted)
                    }
                    AmountField(title: split ? String(localized: "Left") : String(localized: "Pumped"), symbol: "drop.halffull", color: LogStyle.apricot, draft: $volume, component: .first, focus: $focusedField, focusValue: .milk)
                    if split {
                        AmountField(
                            title: String(localized: "Right"), symbol: "drop.halffull", color: LogStyle.apricot,
                            draft: $volume,
                            component: .second, focus: $focusedField, focusValue: .formula
                        ).transition(.opacity)
                    }
                    if selectedProfile != nil && (try? volume.validated()) == nil {
                        Text("Enter the amount pumped to enable Save.").font(.footnote).foregroundStyle(LogStyle.muted)
                    }
                    EventTimeField(date: $occurredAt)
                    DisclosureGroup {
                        TextField("Duration in minutes (optional)", text: $minutes).keyboardType(.decimalPad).focused($focusedField, equals: .duration).padding(.vertical)
                        TextField("Optional note", text: $note, axis: .vertical).focused($focusedField, equals: .note)
                        if let existing { RevisionHistory(store: store, id: existing.id) }
                    } label: { Text("More details").frame(minHeight: 44) }
                    if let error { ErrorNotice(message: error) }
                    if existing != nil && store.canEdit { Button("Delete pumping session", role: .destructive) { confirmDelete = true } }
                }.padding(24)
                    .animation(
                        reduceMotion || focusedField != nil ? nil : .smooth(duration: 0.2),
                        value: split)
            }.scrollDismissesKeyboard(.interactively).background(LogStyle.canvas)
                .navigationTitle("Pumping").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    if store.canEdit {
                        EditorActionBar(editing: focusedField != nil,
                                        nextTitle: split && focusedField == .milk ? String(localized: "Next: Right") : nil,
                                        next: { focusedField = .formula }, done: { focusedField = nil }) {
                            PrimaryButton(
                                title: existing == nil
                                    ? (volume.total > 0 ? String(localized: "Save \(volume.unit.quantity(volume.total)) pumped") : String(localized: "Save pumping"))
                                    : String(localized: "Save changes"), disabled: selectedProfile == nil || (try? volume.validated()) == nil
                            ) { save() }
                            .accessibilityIdentifier("pumping.save")
                        }
                    }
                }
                .confirmationDialog("Delete this pumping session?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete session", role: .destructive) {
                        guard let existing, let record = store.snapshot.record(existing.id) else { return }
                        do { try store.delete(record); dismiss() } catch { self.error = error.localizedDescription }
                    }
                }
                .sheet(isPresented: $addingProfile) { CaregiverEditor(store: store, existing: nil) }
                .onChange(of: pumpingProfiles.map(\.id)) {
                    if let selectedID = profile.id, !pumpingProfiles.contains(where: { $0.id == selectedID }) {
                        let keptID = store.snapshot.canonicalCaregiverID(selectedID)
                        if pumpingProfiles.contains(where: { $0.id == keptID }) {
                            // A merge can arrive while this draft is open. Preserve typed amounts.
                            selectProfile(keptID, replaceVolume: false)
                            return
                        }
                        profile.id = nil
                        volumePreset = nil
                        return
                    }
                    guard existing == nil, profile.id == nil, pumpingProfiles.count == 1 else { return }
                    // A profile may arrive from iCloud after this form opens. Keep any entered amount.
                    let untouched = volume.firstText.isEmpty && volume.secondText.isEmpty
                    selectProfile(pumpingProfiles[0].id, replaceVolume: untouched)
                }
        }.foregroundStyle(LogStyle.ink).babyPalette(for: nil)
    }

    private var pumpingProfileCard: some View {
        LogCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pumping for").font(.headline)
                if let existing,
                    store.snapshot.record(store.snapshot.canonicalCaregiverID(existing.motherID))?
                        .isDeleted
                        == true
                {
                    Text(
                        "This session belongs to a deleted profile. Choose another pumping profile to move it, or restore the original profile in Settings → Review edits & deleted entries."
                    )
                    .font(.subheadline).foregroundStyle(LogStyle.muted)
                }
                if pumpingProfiles.count == 1, let selectedProfile {
                    Label(selectedProfile.name, systemImage: "drop.halffull").font(.title3.weight(.semibold))
                } else if !pumpingProfiles.isEmpty {
                    Picker("Pumping profile", selection: Binding(get: { profile.id }, set: { selectProfile($0) })) {
                        Text("Choose who pumped").tag(nil as UUID?)
                        ForEach(pumpingProfiles) { Text($0.name).tag(Optional($0.id)) }
                    }.pickerStyle(.menu).controlSize(.large).frame(minHeight: 44)
                        .accessibilityIdentifier("pumping.profile")
                    if selectedProfile == nil {
                        Text("Choose a pumping profile to enable Save.").font(.footnote).foregroundStyle(LogStyle.muted)
                    }
                } else {
                    Text("Add the person who pumps. Your own profile doesn’t need pumping enabled.")
                        .font(.subheadline).foregroundStyle(LogStyle.muted)
                    Button { addingProfile = true } label: {
                        Label("Add pumping profile", systemImage: "person.crop.circle.badge.plus")
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                    }.disabled(!store.canEdit)
                }
                Label(
                    "Recorded by \(store.snapshot.caregiverName(existing?.authorID ?? store.caregiverID))",
                    systemImage: "person.crop.circle"
                )
                .font(.footnote).foregroundStyle(LogStyle.muted)
            }
        }
    }

    private func selectProfile(_ id: UUID?, replaceVolume: Bool = true) {
        guard profile.id != id else { return }
        profile.id = id
        guard existing == nil else { return }
        if replaceVolume {
            volumePreset = PumpVolumePreset.latest(for: id, in: store.snapshot)
            volume = volumePreset?.draft(unit: volume.unit) ?? VolumeDraft(unit: volume.unit)
            split = volumePreset?.split ?? false
        } else {
            volumePreset = nil
        }
        focusedField = nil
    }
    private func changeEntryMode(_ newValue: Bool) {
        guard split != newValue else { return }
        // Only an explicit mode change resets the amounts, not loading another profile's preset.
        if newValue {
            volume = VolumeDraft(unit: volume.unit)
        } else {
            volume = VolumeDraft(unit: volume.unit, firstML: volume.total, secondML: 0)
        }
        split = newValue
        focusedField = nil
    }
    private func save() {
        do {
            guard let family = store.snapshot.family, let motherID = profile.id else { return }
            let (first, second) = try volume.validated()
            let duration = Decimal.input(minutes)
            if !minutes.isEmpty && duration == nil { throw LogError.message(String(localized: "Enter a valid duration.")) }
            let session = PumpSession(id: id, familyID: family.id, motherID: motherID, occurredAt: occurredAt, createdAt: existing?.createdAt ?? .now, authorID: existing?.authorID ?? store.caregiverID, source: existing?.source ?? "App", totalML: first + second, leftML: split ? first : nil, rightML: split ? second : nil, unit: volume.unit, minutes: duration, note: note, importIdentity: existing?.importIdentity, timeZoneIdentifier: existing?.timeZoneIdentifier)
            try store.save(.pumping(session), parentIDs: parents, commandID: commandID)
            store.toast = String(localized: "Pumping saved for \(store.snapshot.caregiverName(motherID))")
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
