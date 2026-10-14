import SwiftUI
import CloudKit
import CoreData
import AppIntents

struct SettingsView: View {
    @Bindable var store: LogStore
    @Environment(\.demoSession) private var demoSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var childEditor: ChildEditRoute?
    @State private var caregiverEditor: CaregiverEditRoute?
    @State private var invite = false
    @State private var timeZone = ""
    @State private var confirmZone = false
    @State private var confirmFamilyDeletion = false
    @State private var showingDemo = false
  @State private var copiedSyncDiagnostics = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Our little circle", systemImage: "person.2.fill").font(LogStyle.heading(.title2)).foregroundStyle(LogStyle.forest)
                        Text("One family. Every child. Everyone in the loop.").foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                }.listRowBackground(LogStyle.sage)
                Section {
                    ForEach(store.snapshot.children) { child in
                        Button { childEditor = ChildEditRoute(child: child) } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(BabyPalette(gender: child.paletteGender).accent)
                                Text(child.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.forward").font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 4)
                        }
                    }
                    Button("Add child", systemImage: "plus") { childEditor = ChildEditRoute() }.disabled(!store.canEdit)
                } header: { Text("Children") } footer: { Text("Caregivers share access to every current and future child in this family.") }
                Section("Caregivers & sharing") {
                    ForEach(store.snapshot.caregivers) { person in
                        Button { caregiverEditor = CaregiverEditRoute(person: person) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(person.name).foregroundStyle(.primary)
                                    if person.cloudIdentity != nil || person.invitation != nil {
                                        Text(
                                            person.cloudIdentity != nil ? String(localized: "Apple Account linked") : String(localized: "Invitation started")
                                        )
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if person.id == store.caregiverID { Text("You").foregroundStyle(.secondary) }
                                if person.isMother { Image(systemName: "drop.halffull").accessibilityLabel("Pumping profile") }
                            }
                        }
                    }
                    if !store.isDemo {
                        Button(store.isOwner ? String(localized: "Invite or manage caregivers") : String(localized: "Manage family access"), systemImage: "person.badge.plus") { invite = true }
                    }
                    Button("Add pumping profile", systemImage: "drop.halffull") { caregiverEditor = CaregiverEditRoute() }.disabled(!store.canEdit)
                }
                Section {
                    Picker("Volume", selection: $store.volumeUnit) { ForEach(VolumeUnit.allCases) { Text($0 == .ml ? String(localized: "Milliliters") : String(localized: "Ounces")).tag($0) } }
                    if !store.isDemo {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        } label: {
                            Label("App language", systemImage: "globe")
                        }.accessibilityHint("Choose your preferred app language in iPhone Settings.")
                    }
                } header: { Text("Preferences") } footer: { Text("Swaddle uses 1 oz = 30 mL for volume entry and display. Changing units preserves saved amounts.") }
                Section("Siri & widgets") {
                    NavigationLink { SiriSetupView(store: store, childName: store.snapshot.children.count == 1 ? String(localized: "my baby") : store.selectedChild?.name ?? String(localized: "my baby")) } label: { Label("Siri", systemImage: "waveform") }
                    NavigationLink { WidgetHelpView(store: store) } label: { Label("Home & Lock Screen widgets", systemImage: "square.grid.2x2") }
                }
                Section {
                    NavigationLink { RecoveryView(store: store) } label: {
                        Label("Review edits & deleted entries", systemImage: "clock.arrow.circlepath")
                    }
                    LabeledContent("Status", value: store.syncMessage)
                    if store.persistence.cloudEnabled {
                        Button {
                            Task { await store.syncCloud() }
                        } label: {
                            HStack {
                                Label(store.isSyncing ? String(localized: "Syncing…") : String(localized: "Sync now"), systemImage: "arrow.triangle.2.circlepath")
                                Spacer()
                                if store.isSyncing { ProgressView() }
                            }
                        }.disabled(store.isSyncing)
                        if store.pendingUploadCount > 0 { LabeledContent("Waiting to upload", value: "\(store.pendingUploadCount)") }
            Button(
              copiedSyncDiagnostics ? String(localized: "Diagnostics copied") : String(localized: "Copy sync diagnostics"),
              systemImage: copiedSyncDiagnostics ? "checkmark" : "doc.on.doc"
            ) {
              UIPasteboard.general.string = store.syncDiagnostic
              copiedSyncDiagnostics = true
            }
                    }
                    if let last = store.lastUpload { LabeledContent("Last upload", value: last.formatted(date: .abbreviated, time: .shortened)) }
                    if let last = store.lastSync { LabeledContent("Last checked iCloud", value: last.formatted(date: .abbreviated, time: .shortened)) }
                    if store.isDemo {
                        Text("All records are fictional. You can change them freely; they never sync to iCloud or appear in your widgets or Siri.").font(.footnote).foregroundStyle(.secondary)
                    } else if !store.persistence.cloudEnabled {
                        Text("This Simulator build saves locally. Sharing becomes available in a signed device build with iCloud configured.").font(.footnote).foregroundStyle(.secondary)
                    }
                    LabeledContent("Reporting time zone", value: store.snapshot.family?.timeZoneIdentifier ?? TimeZone.current.identifier)
                    if store.canEdit {
                        Button("Change reporting time zone") { timeZone = store.snapshot.family?.timeZoneIdentifier ?? TimeZone.current.identifier; confirmZone = true }
                    }
                } header: { Text("Data & recovery") } footer: { Text("Local saves work offline. iCloud updates are eventual; a save doesn’t confirm another caregiver has received it.") }
                if let demoSession {
                    Section {
                        if store.isDemo {
                            Button("Exit demo", systemImage: "rectangle.portrait.and.arrow.right") { demoSession.exit() }
                        } else {
                            Button("Explore a demo", systemImage: "sparkles") { showingDemo = true }
                        }
                    }
                }
                Section {
                    Link(destination: URL(string: "https://swaddle-ios.app/privacy/")!) {
                        Label("Privacy policy", systemImage: "hand.raised")
                    }.accessibilityIdentifier("settings.privacy")
                    Link(destination: URL(string: "https://swaddle-ios.app/support/")!) {
                        Label("Support", systemImage: "questionmark.circle")
                    }.accessibilityIdentifier("settings.support")
                }
                if store.isOwner && !store.isDemo {
                    Section {
                        Button("Delete family and all records", role: .destructive) { confirmFamilyDeletion = true }
                    } footer: { Text("To keep your records and remove access instead, use Invite or manage caregivers.") }
                }
                Section {
                    Text("Made for the small hours.").font(.headline).foregroundStyle(LogStyle.forest)
                    Text("Your log is a record of care. No scores, streaks, or feeding targets.").font(.footnote).foregroundStyle(.secondary)
                }.listRowBackground(Color.clear)
            }.scrollContentBackground(.hidden).background(LogStyle.canvas).navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .sheet(item: $childEditor) { ChildEditor(store: store, existing: $0.child) }
                .sheet(item: $caregiverEditor) { CaregiverEditor(store: store, existing: $0.person) }
                .sheet(isPresented: $invite) { InviteCaregiverView(store: store) }
                .sheet(isPresented: $showingDemo) { DemoIntroductionView() }
                .confirmationDialog("Permanently delete this family?", isPresented: $confirmFamilyDeletion, titleVisibility: .visible) {
                    Button("Delete family and all records", role: .destructive) {
                        do { try store.deleteFamily() } catch { store.report(error) }
                    }
                } message: { Text("All children, activity, pumping, and change history will be removed. This cannot be undone. Other caregivers’ copies update when they sync.") }
                .alert("Reporting time zone", isPresented: $confirmZone) {
                    TextField("e.g. America/New_York", text: $timeZone).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Cancel", role: .cancel) {}
                    Button("Change") { do { try store.setReportingZone(timeZone) } catch { store.report(error) } }
                } message: { Text("Changing this family setting re-groups calendar charts for every caregiver. Rolling 24-hour totals stay the same.") }
        }.babyPalette(for: nil)
    }
}

/// The tab shell shares one presentation for buttons and deep links; standalone previews own it locally.
struct SettingsButton: View {
    let store: LogStore
    var presentation: Binding<Bool>? = nil
    @State private var presented = false
    var body: some View {
        Button {
            if let presentation { presentation.wrappedValue = true }
            else { presented = true }
        } label: {
            Image(systemName: "gearshape").frame(width: 44, height: 44)
        }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("app.settings")
            .sheet(isPresented: $presented) { SettingsView(store: store) }
    }
}
struct ChildEditRoute: Identifiable { let id = UUID(); var child: ChildProfile? }
struct CaregiverEditRoute: Identifiable { let id = UUID(); var person: Caregiver? }

struct ChildEditor: View {
  let store: LogStore
  let existing: ChildProfile?
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var birthday: Date
  @State private var includeBirthday: Bool
  @State private var includeGestation: Bool
  @State private var gestationalWeeks: Int?
  @State private var gestationalDays: Int
  @State private var gender: ChildGender?
  @State private var growthReferenceSex: GrowthReferenceSex?
  @State private var colorTheme: ChildColorTheme?
  @State private var confirmDelete = false
  @State private var error: String?
  private let id: UUID
  private let parents: Set<UUID>
  init(store: LogStore, existing: ChildProfile?) {
    self.store = store; self.existing = existing; name = existing?.name ?? "";
    birthday = existing?.birthDate ?? .now; includeBirthday = existing?.birthDate != nil
    gender = existing?.gender
    growthReferenceSex = existing?.growthReferenceSex
    colorTheme = existing?.colorTheme
    // The editor owns this draft until Save; remote refreshes must not reset it.
    includeGestation = existing?.gestationalAgeAtBirthDays != nil
    gestationalWeeks = existing?.gestationalAgeAtBirthDays.map { $0 / 7 }
    gestationalDays = existing?.gestationalAgeAtBirthDays.map { $0 % 7 } ?? 0
    id = existing?.id ?? UUID();
    parents = Set(existing.flatMap { store.snapshot.record($0.id) }?.heads.map(\.id) ?? [])
  }
  private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone =
      TimeZone(identifier: store.snapshot.family?.timeZoneIdentifier ?? "") ?? .current
    return value
  }
  private var draft: ChildProfile {
    ChildProfile(
      id: id, familyID: store.snapshot.family?.id ?? id,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      birthDate: includeBirthday ? calendar.startOfDay(for: birthday) : nil,
      gender: gender,
      gestationalAgeAtBirthDays: includeBirthday && includeGestation
        ? gestationalWeeks.map { $0 * 7 + gestationalDays } : nil,
      growthReferenceSex: growthReferenceSex, colorTheme: colorTheme)
  }
  var body: some View {
    NavigationStack {
      Form {
        Section("Child profile") {
          TextField("Name", text: $name).textContentType(.givenName)
          GenderPicker(gender: $gender)
          Toggle("Include birth date", isOn: $includeBirthday)
          if includeBirthday {
            LogDatePicker(title: String(localized: "Born"), selection: $birthday, displayedComponents: .date)
              .environment(\.calendar, calendar)
              .environment(\.timeZone, calendar.timeZone)
          }
        }.disabled(!store.canEdit)
        if includeBirthday {
          Section {
            Toggle("Include gestational age at birth", isOn: $includeGestation)
            if includeGestation {
              Picker("Weeks at birth", selection: $gestationalWeeks) {
                Text("Choose weeks").tag(nil as Int?)
                ForEach(ChildAge.gestationalWeeksRange, id: \.self) { weeks in
                  Text("\(weeks) weeks").tag(Optional(weeks))
                }
              }
              Picker("Additional days", selection: $gestationalDays) {
                ForEach(0...6, id: \.self) { days in
                  Text("\(days) days").tag(days)
                }
              }.disabled(gestationalWeeks == nil)
            }
          } header: {
            Text("Gestational age")
          } footer: {
            Text(
              "Enter the completed weeks and additional days of pregnancy at birth, such as 35 weeks and 4 days. Leave this off if you don’t know."
            )
          }.disabled(!store.canEdit)
          Section("Age") {
            TimelineView(.periodic(from: .now, by: 60)) { context in
              if let age = ChildAge(child: draft, at: context.date, calendar: calendar) {
                ChildAgeReadout(age: age, calendar: calendar)
              }
            }
            DisclosureGroup("About these ages") {
              Text(
                "Age counts from the birth date. Gestational age now adds that age to gestational age at birth; it’s also called postmenstrual age. For babies born before 37 weeks, corrected age counts from the estimated due date at 40 weeks."
              )
              .font(.footnote).foregroundStyle(.secondary)
            }
          }
        }
        Section {
          DisclosureGroup("Advanced growth settings") {
            Picker("Reference", selection: $growthReferenceSex) {
              Text(draft.defaultGrowthReferenceSex.map { String(localized: "Automatic (\($0.title))") } ?? String(localized: "Not set"))
                .tag(nil as GrowthReferenceSex?)
              ForEach(GrowthReferenceSex.allCases) { sex in
                Text(sex.title).tag(Optional(sex))
              }
            }.accessibilityIdentifier("growth.reference")
            Text("The Boys or Girls reference follows your child’s gender unless you choose an override. Appearance never changes percentiles. A birth date is also needed.")
              .font(.footnote).foregroundStyle(.secondary)
            Text("For a preterm birth, add gestational age at birth. Trends uses WHO with corrected age from the estimated due date and also shows an actual-age comparison.")
              .font(.footnote).foregroundStyle(.secondary)
          }
          if includeBirthday && draft.effectiveGrowthReferenceSex == nil {
            Text("Choose Boy or Girl above, or set a reference in Advanced growth settings, to show growth percentiles.")
              .font(.footnote).foregroundStyle(.secondary)
          }
        }.disabled(!store.canEdit)
        Section {
          Picker("Color", selection: $colorTheme) {
            Text("Automatic").tag(nil as ChildColorTheme?)
            ForEach(ChildColorTheme.allCases) { theme in
              Text(theme.title).tag(Optional(theme))
            }
          }.accessibilityIdentifier("child.color")
          Label(name.isEmpty ? String(localized: "Your child") : name, systemImage: "person.crop.circle.fill")
            .font(.headline).foregroundStyle(BabyPalette(gender: draft.paletteGender).accent)
            .frame(maxWidth: .infinity, alignment: .leading).padding()
            .background(BabyPalette(gender: draft.paletteGender).surface, in: .rect(cornerRadius: 18))
        } header: {
          Text("A little color")
        } footer: {
          Text(
            "Automatic uses soft blue for a boy, soft rose for a girl, or sage when not set. You can choose any color for their log and widgets."
          )
        }.disabled(!store.canEdit)
        Section {
          Text(
            "This child and their activity are visible to the family’s current and future caregivers. Feeding defaults and charts stay separate for each child."
          ).font(.footnote).foregroundStyle(.secondary)
        }
        if let error { ErrorNotice(message: error) }
        if existing != nil && store.canEdit {
          Button("Delete child and their history", role: .destructive) { confirmDelete = true }
        }
      }.navigationTitle(existing == nil ? String(localized: "Add child") : String(localized: "Child profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              guard let family = store.snapshot.family else { return }
              do {
                guard draft.familyID == family.id else { return }
                try store.save(.child(draft), parentIDs: parents)
                if existing == nil { store.selectedChildID = id }
                dismiss()
              } catch { self.error = error.localizedDescription }
            }.disabled(
              name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canEdit
                || (includeBirthday && includeGestation && gestationalWeeks == nil))
          }
        }
        .confirmationDialog(
          "Delete \(existing?.name ?? String(localized: "this child"))?", isPresented: $confirmDelete,
          titleVisibility: .visible
        ) {
          Button("Delete child and history", role: .destructive) {
            guard let record = store.snapshot.record(id) else { return }
            do { try store.delete(record); dismiss() } catch {
              self.error = error.localizedDescription
            }
          }
        } message: {
          Text(
            "This removes the child and their activity from your family log and widgets. Siblings and maternal pumping are preserved."
          )
        }
    }.foregroundStyle(LogStyle.ink).babyPalette(for: draft.paletteGender)
  }
}

struct CaregiverEditor: View {
    let store: LogStore
    let existing: Caregiver?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var mother: Bool
    @State private var sex: CaregiverSex?
    @State private var error: String?
    @State private var invitationProfile: Caregiver?
    @State private var deletionCandidate: Caregiver?
    @State private var mergingProfile: Caregiver?
    private var currentProfile: Caregiver? {
        existing.flatMap { person in store.snapshot.caregivers.first { $0.id == person.id } }
    }
    private var deletionBlocker: String? {
        guard let existing else { return nil }
        do {
            _ = try CaregiverDeletionRules.validate(
                existing.id, in: store.snapshot,
                actorID: store.caregiverID, canEdit: store.canEdit)
            return nil
        } catch { return error.localizedDescription }
    }
    private var sexChanged: Bool {
        sex != existing?.sex
    }
    init(store: LogStore, existing: Caregiver?) {
        self.store = store; self.existing = existing
        name = existing?.name ?? ""; mother = existing?.isMother ?? true
        sex = existing?.sex
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display name", text: $name)
                    Picker("Sex (optional)", selection: $sex) {
                        Text("Not specified").tag(nil as CaregiverSex?)
                        ForEach(CaregiverSex.allCases) { sex in Text(sex.title).tag(Optional(sex)) }
                    }.accessibilityIdentifier("caregiver.sex")
                    Toggle("Pumping profile", isOn: $mother)
                } footer: { Text("Not specified keeps neutral adult artwork. Pumping is an independent choice.") }
                .disabled(!store.canEdit)
                if let existing, store.isOwner, !store.isDemo, existing.id != store.caregiverID {
                    Section {
                        Button(name.trimmingCharacters(in: .whitespacesAndNewlines) != existing.name || mother != existing.isMother || sexChanged
                               ? String(localized: "Save and invite this caregiver") : String(localized: "Invite this caregiver"), systemImage: "person.badge.plus") {
                            do { invitationProfile = try saveProfile() }
                            catch { self.error = error.localizedDescription }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canEdit)
                        .accessibilityIdentifier("caregiver.invite")
                    } footer: {
                        Text("Their Apple Account will be linked to this profile, including existing pumping sessions. They’ll be able to edit the whole family log.")
                    }
                }
                if let error { ErrorNotice(message: error) }
                if let currentProfile, store.isOwner, store.snapshot.caregivers.count > 1 {
                    Section {
                        Button("Merge caregiver profiles", systemImage: "person.2") {
                            mergingProfile = currentProfile
                        }
                        .disabled(
                            !store.canEdit
                                || name.trimmingCharacters(in: .whitespacesAndNewlines)
                                    != currentProfile.name
                                || mother != currentProfile.isMother
                                || sexChanged
                        )
                        .accessibilityIdentifier("caregiver.merge")
                    } footer: {
                        Text(
                            "Combine duplicate profiles for the same person while keeping their history. Save any profile changes first."
                        )
                    }
                }
                if let existing {
                    Section {
                        if let blocker = deletionBlocker {
                            Text(blocker).foregroundStyle(.secondary)
                        }
                        Button("Delete caregiver", role: .destructive) {
                            deletionCandidate = currentProfile
                        }
                        .disabled(deletionBlocker != nil)
                        .accessibilityIdentifier("caregiver.delete")
                        let count = store.snapshot.pumps.filter { $0.motherID == existing.id }.count
                        if count > 0 { LabeledContent("Pumping sessions kept", value: "\(count)") }
                    } header: {
                        Text("Delete profile")
                    } footer: {
                        Text(
                            "Saved care entries and names stay in history. You can restore this profile in Settings → Review edits & deleted entries. iCloud invitations and family access are unchanged."
                        )
                    }
                }
            }.navigationTitle(existing == nil ? String(localized: "Add caregiver") : String(localized: "Caregiver")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do { _ = try saveProfile(); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }.disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.canEdit
                                || (existing != nil && currentProfile == nil))
                    }
                }
                .sheet(item: $invitationProfile) { person in
                    InviteThisCaregiverView(store: store, caregiverID: person.id)
                }
                .sheet(item: $mergingProfile) { person in
                    CaregiverMergeView(store: store, caregiverID: person.id)
                }
                .onChange(of: currentProfile?.id) {
                    if existing != nil && currentProfile == nil { dismiss() }
                }
                .confirmationDialog("Delete caregiver?", item: $deletionCandidate, titleVisibility: .visible) { person in
                    Button("Delete \(person.name)", role: .destructive) {
                        do { try store.deleteCaregiver(person.id); dismiss() } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { person in
                    Text(
                        "\(person.name) will be removed from caregivers and new-entry choices. Existing care and pumping history will be kept. This change syncs to your family and can be restored. It does not remove iCloud access."
                    )
                }
        }
    }

    private func saveProfile() throws -> Caregiver {
        guard let family = store.snapshot.family else { throw CloudSharePreparationError.familyChanged }
        // Edit the latest profile so an invitation accepted while this editor is
        // open cannot be cleared by a stale name/pumping draft.
        var person: Caregiver
        if let existing {
            guard let current = store.snapshot.caregivers.first(where: { $0.id == existing.id }) else {
                throw LogError.message(String(localized: "This caregiver profile is no longer available."))
            }
            person = current
        } else {
            person = Caregiver(familyID: family.id, name: name)
        }
        person.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        person.isMother = mother
        // An unchanged sex draft must not overwrite a remote edit. Keep the
        // latest Apple Account and invitation fields when saving the profile.
        person = CaregiverSexEdits.applying(to: person, baseline: existing, sex: sex)
        try store.save(.caregiver(person))
        return person
    }
}

struct PumpHistoryView: View {
    @Bindable var store: LogStore
    let mother: Caregiver
    @State private var route: LogRoute?
    @State private var importing = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: store.snapshot.family?.timeZoneIdentifier ?? "") ?? .current
        return value
    }
    private var entries: [PumpSession] { store.snapshot.pumps.filter { $0.motherID == mother.id } }
    private var canRecord: Bool {
        store.canEdit && store.snapshot.caregivers.contains { $0.id == mother.id && $0.isMother }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if store.snapshot.record(mother.id)?.isDeleted == true {
                    Text(
                        "This profile was deleted. Its pumping history is kept. Restore the profile in Settings → Review edits & deleted entries to record more."
                    )
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                LogCard(color: LogStyle.sage) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Pumped · Last 24 hours").font(.headline)
                        Text(store.volumeUnit.quantity(entries.filter { $0.occurredAt > Date.now.addingTimeInterval(-86400) && $0.occurredAt <= .now }.reduce(0) { $0 + $1.totalML }))
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        Text("Shared family record · Separate from bottle intake").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if entries.isEmpty { ContentUnavailableView("A place for pumping", systemImage: "drop.halffull", description: Text("Sessions for \(mother.name) will appear here.")) }
                else {
                    if !typeSize.isAccessibilitySize {
                        PumpingHistoryChart(
                            entries: Array(entries.prefix(30)), unit: store.volumeUnit,
                            calendar: calendar)
                    }
                    ForEach(entries) { entry in
                        Button { route = LogRoute(pump: entry) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(store.volumeUnit.chartQuantity(entry.totalML)).font(.headline)
                                    Text(entry.occurredAt, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.subheadline).foregroundStyle(.secondary)
                                    Text("Recorded by \(store.snapshot.caregiverName(entry.authorID))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.forward").font(.caption)
                            }.padding(.vertical, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }.padding(22)
        }.refreshable { await store.syncCloud() }
            .background(LogStyle.canvas).navigationTitle("\(mother.name)’s pumping")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    VolumeUnitPicker(unit: $store.volumeUnit)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Import pumping", systemImage: "square.and.arrow.down") { importing = true }
                        .disabled(!canRecord)
                    Button("Record pumping", systemImage: "plus") { route = LogRoute() }.disabled(!canRecord)
                }
            }
            .sheet(item: $route) { PumpEditor(store: store, existing: $0.pump, initialMotherID: mother.id) }
            .sheet(isPresented: $importing) { CareImportView(store: store, pumpingProfile: mother) }
            .modifier(PumpingRecordPresentation(store: store, canPlay: route == nil && !importing))
    }
}

struct InviteCaregiverView: View {
    let store: LogStore
    @Environment(\.dismiss) private var dismiss
    @State private var readOnly = false
    @State private var loading = false
    @State private var share: ShareItem?
    @State private var error: String?
    @State private var preparationTask: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "person.2.wave.2").font(.system(size: 50)).foregroundStyle(LogStyle.forest)
                    Text(store.isOwner ? String(localized: "Bring your people in.") : String(localized: "Your family circle.")).font(.system(.largeTitle, design: .serif, weight: .semibold))
                    Text(store.isOwner ? String(localized: "Invite a partner, grandparent, or caregiver using their own Apple Account.") : String(localized: "View the family’s participants or leave the shared log using Apple’s sharing controls.")).font(.title3).foregroundStyle(.secondary)
                    LogCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("All children, one family", systemImage: "checkmark.circle").font(.headline)
                            Text(store.snapshot.children.map(\.name).joined(separator: ", "))
                            Text("Includes existing history, new children, future activity, and shared pumping. Personal entry defaults stay private.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if store.isOwner {
                        Picker("Access", selection: $readOnly) { Text("Can edit").tag(false); Text("View only").tag(true) }.pickerStyle(.segmented).disabled(loading)
                        Text(readOnly ? String(localized: "Can view all shared activity. Can’t add, change, or delete entries.") : String(localized: "Can add children and record, edit, or delete shared entries across the family.")).font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Leaving ends your access to every child and shared pumping session. Previously synchronized entries remain in the family’s history.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let error { ErrorNotice(message: error) }
                    if loading {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Preparing your iCloud invitation…").font(.subheadline)
                        }.accessibilityElement(children: .combine)
                    }
                    PrimaryButton(title: loading ? String(localized: "Preparing invitation…") : String(localized: "Continue with iCloud"), disabled: loading) {
                        error = nil
                        loading = true
                        preparationTask = Task {
                            defer { loading = false; preparationTask = nil }
                            do {
                                let preparedShare = try await store.prepareShare()
                                try Task.checkCancellation()
                                share = ShareItem(share: preparedShare)
                            }
                            catch is CancellationError { }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    Text("Only invited people can join. An Apple Family Sharing group isn’t required.").font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }.background(LogStyle.canvas).navigationTitle("Family sharing").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $share) { item in
                    CloudShareSheet(share: item.share, readOnly: readOnly, store: store) { failure in
                        share = nil
                        error = failure.localizedDescription
                    }
                }
                .onDisappear { preparationTask?.cancel() }
        }
    }
}
struct ShareItem: Identifiable { var id: String { share.recordID.recordName }; var share: CKShare }
struct CloudShareSheet: UIViewControllerRepresentable {
    let share: CKShare
    let readOnly: Bool
    let store: LogStore
    let onFailure: (Error) -> Void
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CKContainer(identifier: PersistenceController.cloudContainer))
        controller.modalPresentationStyle = .formSheet
        controller.availablePermissions = readOnly ? [.allowPrivate, .allowReadOnly] : [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(store: store, onFailure: onFailure) }
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let store: LogStore
        let onFailure: (Error) -> Void
        init(store: LogStore, onFailure: @escaping (Error) -> Void) {
            self.store = store
            self.onFailure = onFailure
        }
        func itemTitle(for csc: UICloudSharingController) -> String? { String(localized: "Swaddle family") }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) { onFailure(error) }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            guard store.isOwner, let share = csc.share else { store.reload(); return }
            Task { @MainActor in
                do {
                    if !store.persistence.usesCKSyncEngine { _ = try await store.saveShare(share) }
                    await store.syncCloud()
                    store.reload()
                } catch { onFailure(error) }
            }
        }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { Task { await store.syncCloud(); store.reload() } }
    }
}

struct WidgetHelpView: View {
    let store: LogStore
    @State private var unit: VolumeUnit
    init(store: LogStore) {
        self.store = store
        _unit = State(initialValue: store.isDemo ? store.volumeUnit : WidgetCache.unit)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if store.isDemo {
                    Text("Widgets and Siri use your own family log, not the demo.").font(.callout).foregroundStyle(LogStyle.forest)
                }
                Text("A glance is enough.").font(.system(.largeTitle, design: .serif, weight: .semibold))
                LogCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Log from your Home Screen", systemImage: "square.grid.2x2").font(.headline)
                        Text("Care & quick log").font(.headline)
                        Text("Last 24 hours of bottles, family pumping, and diapers, with Pee, Poo, Both, and Bottle actions.")
                        Text("Touch and hold your Home Screen, tap Edit, then Add Widget. Find Swaddle and choose Quick log for all four actions in one row, or add a small Pee, Poo, Both, or Bottle widget.")
                        Text("Choose a child in Edit Widget. With one child, we select them for you. Each widget stays linked to that child, even when you switch children in Swaddle.")
                        Text("Diapers open Swaddle and save now, with confirmation and Undo. Bottle opens the editor with your previous amounts; review and tap Save.")
                        Text("A recently used diaper control briefly becomes Undo. Tapping outside the four actions only opens the log.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                LogCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Log from your Lock Screen", systemImage: "lock.iphone").font(.headline)
                        Text("Pee · Poo · Both · Bottle").font(.headline)
                        Text("Touch and hold your Lock Screen, tap Customize, choose Lock Screen, then tap the widget area below the time. Find Swaddle and add each circular control.")
                        Text("Tap a control while customizing to choose its child. With one child, we select them for you. Each control stays linked to that child.")
                        Text("Tap Pee, Poo, or Both to open Swaddle and save a diaper now. Unlock if asked, then look for the saved confirmation and Undo. Bottle opens your previous amounts for review and Save.")
                        Text("Open Swaddle once after updating if it isn’t in the gallery yet.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Text("Your Home Screen overview").font(.title2.bold())
                Text("Add Swaddle from the Home Screen widget gallery. Choose a child for each widget.").foregroundStyle(.secondary)
                if let child = store.selectedChild {
                    Button {
                        unit = unit == .ml ? .oz : .ml
                        if !store.isDemo { WidgetCache.setUnit(unit) }
                    } label: {
                        LogCard(color: BabyPalette(gender: child.paletteGender).surface) {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(child.name).font(.headline)
                                Text("Last 24 hours").font(.caption).foregroundStyle(.secondary)
                                let summary = ActivitySummary(activities: store.snapshot.activities, childID: child.id, start: .now.addingTimeInterval(-86400))
                                Text(unit.quantity(summary.totalML)).font(.largeTitle.bold())
                                Text("\(unit.quantity(summary.milkML)) milk · \(unit.quantity(summary.formulaML)) formula").font(.subheadline)
                                if summary.unknownML > 0 { Text("\(unit.quantity(summary.unknownML)) split not recorded").font(.subheadline) }
                                Text("\(summary.wet) wet · \(summary.soiled) soiled").font(.subheadline.bold())
                                Text("Tap volume to switch mL ↔ oz").font(.caption)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityLabel("Widget preview. Switch volume units")
                }
                Text("Tapping a widget’s volume changes its display units without opening the app. Your saved entries and other caregivers’ preferences stay the same.")
                Text("The “as of” time shows when activity last refreshed. Widgets update on the system’s schedule and redact sensitive content when appropriate.").font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
        }.background(LogStyle.canvas).navigationTitle("Widgets").navigationBarTitleDisplayMode(.inline)
    }
}
