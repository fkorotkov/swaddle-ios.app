import SwiftUI

struct CaregiverMergeView: View {
    let store: LogStore
    let caregiverID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var otherID: UUID?
    @State private var keepID: UUID?
    @State private var confirmation: CaregiverMergePlan?
    @State private var error: String?

    init(store: LogStore, caregiverID: UUID, initialOtherID: UUID? = nil) {
        self.store = store
        self.caregiverID = caregiverID
        _otherID = State(initialValue: initialOtherID)
        let canKeepOther =
            initialOtherID.map {
                (try? CaregiverMergeRules.plan(
                    sourceID: caregiverID, destinationID: $0,
                    in: store.snapshot, actorID: store.caregiverID, canEdit: store.canEdit)) != nil
            } ?? false
        _keepID = State(
            initialValue: initialOtherID == nil ? nil : canKeepOther ? initialOtherID : caregiverID)
    }

    private var person: Caregiver? { store.snapshot.caregivers.first { $0.id == caregiverID } }
    private var others: [Caregiver] { store.snapshot.caregivers.filter { $0.id != caregiverID } }
    private var pair: [Caregiver] {
        [person, others.first { $0.id == otherID }].compactMap { $0 }
    }
    private var review: Result<CaregiverMergePlan, Error> {
        Result {
            guard pair.count == 2, let keepID, let source = pair.first(where: { $0.id != keepID }),
                pair.contains(where: { $0.id == keepID })
            else { throw LogError.message(String(localized: "Choose the other profile and which profile to keep.")) }
            return try plan(source: source.id, keeping: keepID)
        }
    }
    private var reviewedPlan: CaregiverMergePlan? { try? review.get() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("One person, one profile.").font(.title2.bold())
                    Text(
                        "Combine duplicate profiles for the same caregiver. Every care entry and pumping session is kept."
                    )
                    .foregroundStyle(.secondary)
                }
                Section("Profiles to combine") {
                    if let person { profileSummary(person) }
                    Picker("Other profile", selection: $otherID) {
                        Text("Choose a profile").tag(Optional<UUID>.none)
                        ForEach(others) { candidate in
                            profileSummary(candidate).tag(Optional(candidate.id))
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("caregiver.merge.other")
                }
                if pair.count == 2 {
                    Section {
                        ForEach(pair) { candidate in
                            Button {
                                keepID = candidate.id
                                error = nil
                            } label: {
                                HStack(spacing: 12) {
                                    Image(
                                        systemName: keepID == candidate.id
                                            ? "checkmark.circle.fill" : "circle"
                                    )
                                    .accessibilityHidden(true)
                                    profileSummary(candidate)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(.rect)
                            }
                            .accessibilityAddTraits(keepID == candidate.id ? .isSelected : [])
                            .accessibilityIdentifier("caregiver.merge.keep.\(candidate.id)")
                        }
                    } header: {
                        Text("Profile to keep")
                    } footer: {
                        Text(
                            "Keep the profile linked to their Apple Account or invitation. Its name and sign-in stay the same."
                        )
                    }
                    Section {
                        if let plan = reviewedPlan {
                            LabeledContent(
                                "Pumping sessions together", value: "\(plan.pumpingCount)")
                            Label(
                                "Original records and authors kept", systemImage: "checkmark.shield"
                            )
                            Label(
                                "iCloud access stays the same",
                                systemImage: "person.crop.circle.badge.checkmark")
                        } else if case .failure(let issue) = review {
                            Text(issue.localizedDescription).foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text(
                            "You can separate profiles in Settings → Review edits & deleted entries. Update Swaddle on every family device before merging."
                        )
                    }
                }
                if let error { Section { ErrorNotice(message: error) } }
            }
            .navigationTitle("Merge profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") { confirmation = reviewedPlan }
                        .disabled(reviewedPlan == nil)
                        .accessibilityIdentifier("caregiver.merge.confirm")
                }
            }
            .onChange(of: otherID) { chooseRecommendedProfile() }
            .confirmationDialog(
                "Merge these profiles?", item: $confirmation, titleVisibility: .visible
            ) {
                plan in
                Button("Merge into \(plan.destination.name)") {
                    do {
                        try store.mergeCaregivers(plan)
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
                Button("Cancel", role: .cancel) {}
            } message: { plan in
                Text(
                    "Keep \(plan.destination.name)’s profile with \(sessionCount(plan.pumpingCount)). Every original entry is kept, and this change syncs to your family. Update Swaddle on every family device first."
                )
            }
        }
    }

    private func profileSummary(_ candidate: Caregiver) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(candidate.name).foregroundStyle(.primary)
            Text(
                candidate.cloudIdentity != nil
                    ? String(localized: "Apple Account linked")
                    : candidate.invitation != nil ? String(localized: "Invitation started") : String(localized: "Unlinked profile")
            )
            .font(.subheadline).foregroundStyle(.secondary)
            Text(
                "\(sessionCount(store.snapshot.pumps.filter { $0.motherID == candidate.id }.count))\(candidate.id == store.caregiverID ? String(localized: " · You") : "")"
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func sessionCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 pumping session") : String(localized: "\(count) pumping sessions")
    }

    private func plan(source: UUID, keeping destination: UUID) throws -> CaregiverMergePlan {
        try CaregiverMergeRules.plan(
            sourceID: source, destinationID: destination, in: store.snapshot,
            actorID: store.caregiverID, canEdit: store.canEdit)
    }

    private func chooseRecommendedProfile() {
        error = nil
        guard let otherID else {
            keepID = nil
            return
        }
        // Favor the existing account/invitation by choosing a permitted direction.
        if (try? plan(source: caregiverID, keeping: otherID)) != nil {
            keepID = otherID
        } else {
            keepID = caregiverID
        }
    }
}

#if DEBUG
    #Preview("Merge profiles · Linked account") {
        CaregiverMergePreview()
    }

    #Preview("Merge profiles · Large dark") {
        CaregiverMergePreview()
            .preferredColorScheme(.dark).environment(\.dynamicTypeSize, .accessibility3)
    }

    private struct CaregiverMergePreview: View {
        let store: LogStore = {
            let store = PreviewData.pumpingHelperStore(profiles: 2)
            do {
                if var person = store.snapshot.caregivers.first(where: { $0.name == "Jamie" }) {
                    person.name = "Alex"
                    person.cloudIdentity = "preview-linked-account"
                    try store.save(.caregiver(person))
                }
            } catch { assertionFailure("Caregiver merge preview failed: \(error)") }
            return store
        }()

        var body: some View {
            if let original = store.snapshot.caregivers.first(where: {
                $0.name == "Alex" && $0.cloudIdentity == nil
            }),
                let linked = store.snapshot.caregivers.first(where: { $0.cloudIdentity != nil })
            {
                CaregiverMergeView(
                    store: store, caregiverID: original.id, initialOtherID: linked.id)
            }
        }
    }
#endif
