import SwiftUI

struct MilestoneCheckInView: View {
    let store: LogStore
    let route: MilestoneCheckInRoute
    let onSave: (UUID) -> Void
    @State private var status: MilestoneStatus?
    @State private var note: String
    @State private var noteExpanded: Bool
    @State private var includeDate: Bool
    @State private var firstDate: Date
    @State private var concern: Bool
    @State private var error: String?
    @State private var discard = false
    @State private var commandID = UUID()
    @FocusState private var noteFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    private let parents: Set<UUID>?

    // A sheet owns one draft; remote changes do not replace unsaved input. The
    // opening revision heads are preserved so simultaneous corrections conflict.
    init(store: LogStore, route: MilestoneCheckInRoute, onSave: @escaping (UUID) -> Void) {
        self.store = store; self.route = route; self.onSave = onSave
        #if DEBUG && targetEnvironment(simulator)
        let reviewStatus: MilestoneStatus? = MotionReview.has("--milestone-seen") ? .seen : MotionReview.has("--milestone-unsure") ? .unsure : nil
        #else
        let reviewStatus: MilestoneStatus? = nil
        #endif
        status = route.observation?.status ?? reviewStatus
        note = route.observation?.note ?? ""
        noteExpanded = !(route.observation?.note.isEmpty ?? true)
        includeDate = route.observation?.firstNoticedAt != nil || reviewStatus == .seen
        firstDate = route.observation?.firstNoticedAt ?? route.observation?.recordedAt ?? .now
        concern = route.observation?.hasConcern ?? false
        parents = route.observation.map { Set(store.snapshot.record($0.id)?.heads.map(\.id) ?? []) }
    }
    private var isDirty: Bool {
        status != route.observation?.status || note != (route.observation?.note ?? "")
            || concern != (route.observation?.hasConcern ?? false)
            || (status == .seen && includeDate ? firstDate : nil) != route.observation?.firstNoticedAt
    }
    private var familyObservations: [MilestoneObservation] {
        store.snapshot.milestoneObservations.filter { $0.childID == route.child.id && $0.skillID == route.skill.id }
    }
    private var latestDate: Date { route.observation?.recordedAt ?? .now }
    private var dateRange: ClosedRange<Date> { min(route.child.birthDate ?? .distantPast, latestDate)...latestDate }
    private var illustrationCaregiverSex: CaregiverSex? {
        let viewerID = store.snapshot.canonicalCaregiverID(store.caregiverID)
        return store.snapshot.caregivers.first { $0.id == viewerID }?.sex
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    heading
                    MilestoneIllustrationView(skill: route.skill, caregiverSex: illustrationCaregiverSex)
                    if let window = route.skill.motorWindow { motorWindow(window) }
                    else if let months = route.skill.months {
                        Text("From CDC’s \(MilestoneCatalog.title(at: months).lowercased()) checklist. These are skills most children (75% or more) show by that age.")
                            .font(.subheadline).foregroundStyle(LogStyle.muted)
                    }
                    if store.canEdit { observationForm }
                    else { Label("Your family access is view only", systemImage: "eye").font(.subheadline) }
                    if let error { ErrorNotice(message: error) }
                    if !familyObservations.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Your family noticed").font(LogStyle.heading(.title2))
                            ForEach(familyObservations) { observation in
                                MilestoneObservationSummary(observation: observation, snapshot: store.snapshot)
                                Divider()
                            }
                            Text("A new observation adds to the story. Earlier check-ins and their first-noticed dates stay in history.")
                                .font(.caption).foregroundStyle(LogStyle.muted)
                        }
                    }
                    if let observation = route.observation,
                       store.history(for: observation.id).count > 1 {
                        DisclosureGroup("Earlier versions of this observation") {
                            ForEach(store.history(for: observation.id)) { revision in
                                if case .milestone(let previous) = revision.value {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("\(revision.date.formatted(date: .abbreviated, time: .shortened)) · \(store.snapshot.caregiverName(revision.editorID))").font(.caption)
                                        Text(previous.status.title).font(.subheadline.weight(.semibold))
                                        if !previous.note.isEmpty { Text(previous.note).font(.subheadline) }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                                }
                            }
                        }
                    }
                    MilestoneConcernNotice()
                    NavigationLink { MilestoneSourcesView() } label: {
                        Label("Source & how to use this", systemImage: "book")
                            .frame(minHeight: 44)
                    }
                    if let url = URL(string: route.skill.localizedSourceURL) {
                        Link("Read this on \(route.skill.publisher)", destination: url).frame(minHeight: 44)
                    }
                    Text("Source: \(route.skill.publisher) · \(route.observation?.sourceVersion ?? route.skill.sourceVersion)")
                        .font(.caption2).foregroundStyle(LogStyle.muted)
                }.padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 24)
                    .frame(maxWidth: 600).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
                .background(LogStyle.canvas)
                .navigationTitle(route.observation == nil ? String(localized: "Check-in for \(route.child.name)") : String(localized: "Observation"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(store.canEdit ? String(localized: "Cancel") : String(localized: "Done")) {
                            if isDirty { discard = true } else { dismiss() }
                        }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer(); Button("Done") { noteFocused = false }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if store.canEdit {
                        PrimaryButton(title: route.observation == nil ? String(localized: "Save observation") : String(localized: "Save changes"), disabled: status == nil || note.count > 2000) { save() }
                            .frame(maxWidth: 556).padding(.horizontal, 22).padding(.vertical, 14)
                            .frame(maxWidth: .infinity).background(.bar)
                    }
                }
                .interactiveDismissDisabled(isDirty)
                .confirmationDialog("Discard your changes?", isPresented: $discard, titleVisibility: .visible) {
                    Button("Discard changes", role: .destructive) { dismiss() }
                    Button("Keep editing", role: .cancel) {}
                }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(route.observation?.localizedTitle ?? route.skill.localizedTitle).font(LogStyle.heading(.largeTitle))
                .tracking(-0.5).fixedSize(horizontal: false, vertical: true)
            Label("\(route.skill.publisher) · \(route.skill.domain.title)", systemImage: route.skill.domain.symbol)
                .font(.caption.weight(.medium)).foregroundStyle(LogStyle.forest)
                .padding(.horizontal, 12).padding(.vertical, 7).background(LogStyle.sage, in: .capsule)
            if let observation = route.observation {
                Text("Recorded \(observation.recordedAt.formatted(date: .abbreviated, time: .omitted)) by \(store.snapshot.caregiverName(observation.authorID))")
                    .font(.caption).foregroundStyle(LogStyle.muted)
                if store.snapshot.record(observation.id)?.hasConflict == true {
                    Text("This observation has competing edits. Review both versions in Settings → Review edits & deleted entries.")
                        .font(.subheadline).foregroundStyle(LogStyle.amber)
                }
            }
        }
    }

    private var observationForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your observation").font(.headline)
            VStack(spacing: 8) {
                ForEach(MilestoneStatus.allCases) { choice in statusButton(choice) }
            }
            if status == .seen {
                VStack(spacing: 8) {
                    Toggle("Add first-noticed date", isOn: $includeDate).font(.subheadline).frame(minHeight: 44)
                    if includeDate {
                        LogDatePicker(title: String(localized: "First noticed"), selection: $firstDate, range: dateRange, displayedComponents: .date)
                            .transition(.opacity)
                    }
                }.animation(reduceMotion ? nil : .smooth(duration: 0.22), value: includeDate)
            }
            DisclosureGroup(isExpanded: $noteExpanded) {
                TextField("What would you like to remember?", text: $note, axis: .vertical).lineLimit(3...6)
                    .focused($noteFocused).padding(.top, 10)
                    .accessibilityIdentifier("milestones.note")
                if note.count > 1800 { Text("\(note.count)/2,000 characters").font(.caption).foregroundStyle(note.count > 2000 ? .red : LogStyle.muted) }
            } label: {
                Label(note.isEmpty ? String(localized: "Add a note (optional)") : String(localized: "Your note"), systemImage: "note.text")
                    .font(.subheadline).foregroundStyle(LogStyle.ink).frame(minHeight: 44)
            }
            .padding(.horizontal, 14).padding(.vertical, 8).background { MilestonePaper() }
            .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: noteExpanded)
            Toggle("I have a concern", isOn: $concern).font(.subheadline).frame(minHeight: 44)
            if concern || status == .lost {
                LogCard(color: LogStyle.apricot, verticalPadding: 16) {
                    Text("If a skill has been lost or you have a concern, contact your child’s doctor and ask about developmental screening. Don’t wait for the next chapter.")
                        .font(.subheadline)
                }
            }
        }.sensoryFeedback(.selection, trigger: status)
    }

    private func statusButton(_ choice: MilestoneStatus) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) { status = choice }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: status == choice ? "checkmark.circle.fill" : "circle")
                    .contentTransition(.symbolEffect(.replace)).symbolEffectsRemoved(reduceMotion)
                    .font(.title3).foregroundStyle(status == choice ? LogStyle.forest : LogStyle.muted)
                Text(choice.title).font(.body.weight(status == choice ? .semibold : .regular))
                Spacer(minLength: 0)
            }.foregroundStyle(LogStyle.ink)
                .padding(.horizontal, 14).padding(.vertical, 11).frame(maxWidth: .infinity, minHeight: 48)
                .background(status == choice ? LogStyle.sage : LogStyle.card.opacity(scheme == .dark ? 0.7 : 0.35), in: .rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18).strokeBorder(status == choice ? LogStyle.forest : LogStyle.muted.opacity(0.25), lineWidth: 1)
                }
        }.buttonStyle(LogPressStyle())
            .accessibilityAddTraits(status == choice ? .isSelected : [])
            .accessibilityIdentifier("milestones.status.\(choice.rawValue)")
    }

    private func motorWindow(_ range: ClosedRange<Double>) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 12) {
                if !typeSize.isAccessibilitySize {
                    Capsule().fill(LogStyle.forest.opacity(0.23)).frame(height: 4).padding(.horizontal, 8)
                        .overlay(alignment: .leading) { Circle().fill(LogStyle.forest).frame(width: 10, height: 10) }
                        .overlay(alignment: .trailing) { Circle().fill(LogStyle.forest).frame(width: 10, height: 10) }
                        .accessibilityHidden(true)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(range.lowerBound.formatted(.number.precision(.fractionLength(1)))) months")
                    Spacer(minLength: 8)
                    Text("\(range.upperBound.formatted(.number.precision(.fractionLength(1)))) months")
                }.font(.subheadline.weight(.medium))
                Text("Observed window · 1st–99th percentile").font(.caption).foregroundStyle(LogStyle.muted)
            }.padding(18).background { MilestonePaper(tone: .sage) }
            Text("A broad reference range, not a due date.")
                .font(.caption).foregroundStyle(LogStyle.muted).multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("WHO observed achievement window, \(range.lowerBound.formatted()) to \(range.upperBound.formatted()) months. First to ninety-ninth percentile. A broad reference range, not a due date or a score for your child.")
    }

    private func save() {
        guard let status else { return }
        do {
            var observation = route.observation ?? MilestoneObservation(
                id: route.id, familyID: route.child.familyID, childID: route.child.id, skillID: route.skill.id,
                sourceVersion: route.skill.sourceVersion, skillTitle: route.skill.title,
                status: status, authorID: store.caregiverID)
            observation.status = status
            observation.firstNoticedAt = status == .seen && includeDate ? firstDate : nil
            observation.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            observation.hasConcern = concern
            try store.save(.milestone(observation), parentIDs: parents, commandID: commandID)
            onSave(observation.id)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct MilestoneObservationSummary: View {
    let observation: MilestoneObservation
    let snapshot: FamilySnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(observation.status.title, systemImage: observation.status.symbol).font(.headline)
            Text("\(snapshot.caregiverName(observation.authorID)) · \(observation.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(LogStyle.muted)
            if let first = observation.firstNoticedAt { Text("First noticed \(first.formatted(date: .abbreviated, time: .omitted))").font(.subheadline) }
            if !observation.note.isEmpty { Text(observation.note).font(.subheadline) }
            if observation.hasConcern { Label("Concern noted", systemImage: "bubble.left").font(.caption) }
            if snapshot.record(observation.id)?.hasConflict == true { Text("Competing edits · Review in Settings").font(.caption).foregroundStyle(LogStyle.amber) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MilestoneConcernNotice: View {
    var body: some View {
        Text("If your child is missing an age-appropriate milestone, has lost a skill, or you have any concern, talk with their doctor and ask about developmental screening. Don’t wait for another check-in.")
            .font(.footnote).foregroundStyle(LogStyle.muted).fixedSize(horizontal: false, vertical: true)
    }
}

struct MilestoneSourcesView: View {
    var body: some View {
        List {
            Section("A journal to share with your family") {
                Text("Checklists help you notice and discuss development. They do not diagnose a delay or replace standardized developmental screening. There is no development score.")
                MilestoneConcernNotice()
            }
            Section("Source: CDC") {
                Text("The age checklists describe what most children (75% or more) do by an age. Swaddle includes 2, 4, 6, 9, 12, 15, 18, and 24 months. Between ages, use the younger checklist; the next chapter is for looking ahead.")
                Text("Checklist wording was developed by CDC and reviewed against its official pages on October 10, 2026. The same material is available free on CDC’s website. CDC, HHS, and the U.S. Government do not endorse Swaddle.")
                Link("CDC milestone checklists", destination: URL(string: MilestoneCatalog.localizedCDCURL)!)
            }
            Section("When a baby was born early") {
                Text("For a birth before 37 weeks, chapters use age measured from the estimated 40-week due date until the second birthday. Add gestational age in Settings. When it is unknown, the app uses birth age; check the age choice with your clinician if your baby was premature.")
                Link("CDC age-checklist guidance", destination: URL(string: MilestoneCatalog.ageGuidanceURL)!)
            }
            Section("Source: WHO") {
                Text("The six motor-development windows come from the WHO Motor Development Study (2006). Their limits describe the 1st and 99th percentiles of observed achievement ages. They are not a deadline or a personalized prediction.")
                Text("WHO and CDC use different definitions and methods. Observations are kept separately; recording one never checks off another. Hands-and-knees crawling is not a prerequisite for recording walking.")
                Link("WHO motor-development standards", destination: URL(string: MilestoneCatalog.whoURL)!)
            }
            Section("Your observations") {
                Text("Unanswered is different from Not yet. Every new check-in keeps its caregiver, date, source version, and optional note. Family members with edit access can correct or delete observations. Deleted entries and competing edits remain available in Settings’ review screen.")
                Text("Observations share with the same family as your care log. Each family member needs this version of Swaddle to read the new records. Milestone records are not included in feeding totals, widgets, or Siri’s care-history search.")
            }
        }.navigationTitle("About milestones").navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden).background(LogStyle.canvas)
    }
}
