import SwiftUI

struct NursingEditor: View {
    let store: LogStore
    let childID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var activity: Activity?
    @State private var parents: Set<UUID>
    @State private var side: BreastSide
    @State private var manual = false
    @State private var correcting = false
    @State private var leftMinutes = ""
    @State private var rightMinutes = ""
    @State private var endedAt = Date.now
    @State private var note = ""
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var feederID: UUID
    private enum Field: Hashable { case left, right, note }
    @FocusState private var focusedField: Field?
    @Environment(\.dynamicTypeSize) private var typeSize
    init(store: LogStore, childID: UUID, existing: Activity?) {
        self.store = store; self.childID = childID; activity = existing
        parents = Set(existing.flatMap { store.snapshot.record($0.id) }?.heads.map(\.id) ?? [])
        feederID = store.caregiverID
        if case .nursing(let session) = existing?.payload { side = session.segments.last?.side ?? .left }
        else { side = .left }
    }
    private var gender: ChildGender? { store.snapshot.children.first { $0.id == childID }?.paletteGender }
    private var palette: BabyPalette { BabyPalette(gender: gender) }
    private var childName: String { store.snapshot.children.first { $0.id == childID }?.name ?? String(localized: "Child unavailable") }
    private var nursing: Nursing? { if case .nursing(let n) = activity?.payload { return n }; return nil }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label(childName, systemImage: "person.crop.circle").foregroundStyle(palette.accent).font(.headline)
                    if let nursing, !correcting {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            NursingClock(nursing: nursing, now: context.date)
                        }
                        if !nursing.finished {
                            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                            layout {
                                Button(nursing.activeSide == nil ? String(localized: "Resume") : String(localized: "Pause"), systemImage: nursing.activeSide == nil ? "play.fill" : "pause.fill") {
                                    update { session, date in
                                        if session.activeSide == nil { session.resume(at: date) } else { session.pause(at: date) }
                                    }
                                }
                                Button("Switch side", systemImage: "arrow.left.arrow.right") {
                                    update { session, date in
                                        session.switchSide(at: date)
                                    }
                                }
                            }.buttonStyle(.bordered).controlSize(.large).buttonBorderShape(.capsule).disabled(!store.canEdit)
                        }
                        Text("Feeding caregiver: \(store.snapshot.caregiverName(nursing.caregiverID))").font(.subheadline).foregroundStyle(.secondary)
                        if let activity { RevisionHistory(store: store, id: activity.id) }
                        if store.canEdit {
                            Button("Correct duration or end time", systemImage: "pencil") {
                                leftMinutes = (nursing.duration(at: .now, side: .left) / 60).formatted(.number.precision(.fractionLength(0...2)))
                                rightMinutes = (nursing.duration(at: .now, side: .right) / 60).formatted(.number.precision(.fractionLength(0...2)))
                                endedAt = nursing.segments.last?.end ?? .now
                                feederID = nursing.caregiverID
                                note = activity?.note ?? ""
                                manual = true; correcting = true
                            }
                            Button(nursing.finished ? String(localized: "Delete session") : String(localized: "Discard session"), role: .destructive) { confirmDelete = true }
                        }
                    } else {
                        if !correcting { Picker("Entry mode", selection: $manual) { Text("Timer").tag(false); Text(typeSize.isAccessibilitySize ? String(localized: "Duration") : String(localized: "Enter duration")).tag(true) }.logPickerStyle() }
                        Picker("Feeding caregiver", selection: $feederID) {
                            ForEach(store.snapshot.caregivers) { Text($0.name).tag($0.id) }
                        }
                        if manual {
                            LogCard {
                                VStack(spacing: 18) {
                                    durationField("Left", text: $leftMinutes, field: .left)
                                    Divider()
                                    durationField("Right", text: $rightMinutes, field: .right)
                                }
                            }
                            EventTimeField(date: $endedAt, title: String(localized: "Finished at"), quickMinutes: [0, 30, 45])
                            TextField("Optional note", text: $note, axis: .vertical).focused($focusedField, equals: .note)
                        } else {
                            Text("Time together.").font(.system(.largeTitle, design: .serif, weight: .semibold)).padding(.top, 20)
                            Text("Start on either side. Pause whenever you need. Your timer stays with \(childName), even when you leave the app.").foregroundStyle(.secondary)
                            Picker("Starting side", selection: $side) { ForEach(BreastSide.allCases) { Text($0.title).tag($0) } }.logPickerStyle()
                            if let last = lastSide {
                                Label("\(store.snapshot.caregiverName(feederID)) last recorded \(last.title)", systemImage: "clock.arrow.circlepath").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let error { ErrorNotice(message: error) }
                }.padding(24)
            }.scrollDismissesKeyboard(.interactively).background(LogStyle.canvas).navigationTitle("Breastfeeding").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(nursing != nil && !correcting ? String(localized: "Done") : String(localized: "Cancel")) { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    if store.canEdit && (nursing?.finished != true || correcting) {
                        EditorActionBar(editing: focusedField != nil,
                                        nextTitle: focusedField == .left ? String(localized: "Next: Right") : nil,
                                        next: { focusedField = .right }, done: { focusedField = nil }) {
                            PrimaryButton(title: correcting ? String(localized: "Save corrected session") : nursing != nil ? String(localized: "Finish feeding") : manual ? String(localized: "Save breastfeeding") : String(localized: "Start \(side.title.lowercased()) side"),
                                          disabled: manual && !validDuration) {
                                if correcting { start() }
                                else if nursing != nil { update { session, date in session.pause(at: date); session.finished = true }; if error == nil { store.toast = String(localized: "Breastfeed saved for \(childName)"); dismiss() } }
                                else { start() }
                            }
                        }
                    }
                }
                .confirmationDialog("Delete this feeding session?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete session", role: .destructive) {
                        guard let id = activity?.id, let record = store.snapshot.record(id) else { return }
                        do { try store.delete(record); dismiss() } catch { self.error = error.localizedDescription }
                    }
                }
        }.foregroundStyle(LogStyle.ink).babyPalette(for: gender)
    }
    private var validDuration: Bool {
        guard let left = leftMinutes.isEmpty ? 0 : Decimal.input(leftMinutes),
              let right = rightMinutes.isEmpty ? 0 : Decimal.input(rightMinutes) else { return false }
        return left >= 0 && right >= 0 && left + right > 0
    }
    private func durationField(_ title: String, text: Binding<String>, field: Field) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(title)
            HStack {
                TextField("Minutes", text: text).keyboardType(.decimalPad).focused($focusedField, equals: field)
                    .multilineTextAlignment(.trailing).frame(minHeight: 44).accessibilityLabel("\(title) duration in minutes")
                Text("min").foregroundStyle(.secondary)
            }
        }.contentShape(.rect).onTapGesture { focusedField = field }
    }
    private var lastSide: BreastSide? {
        store.snapshot.activities.compactMap { event -> (Date, BreastSide)? in
            guard case .nursing(let session) = event.payload, session.caregiverID == feederID, let last = session.segments.last else { return nil }
            return (last.start, last.side)
        }.max { $0.0 < $1.0 }?.1
    }
    private func start() {
        do {
            guard let family = store.snapshot.family else { return }
            var session = Nursing(caregiverID: feederID)
            var date = Date.now
            if manual {
                guard let left = leftMinutes.isEmpty ? 0 : Decimal.input(leftMinutes), let right = rightMinutes.isEmpty ? 0 : Decimal.input(rightMinutes), left >= 0, right >= 0, left + right > 0 else { throw LogError.message(String(localized: "Enter a valid duration greater than zero.")) }
                let total = ((left + right) * 60).double
                date = endedAt.addingTimeInterval(-total)
                var segmentStart = date
                for (side, minutes) in [(BreastSide.left, left), (.right, right)] where minutes > 0 {
                    let end = segmentStart.addingTimeInterval((minutes * 60).double)
                    session.segments.append(NursingSegment(side: side, start: segmentStart, end: end))
                    segmentStart = end
                }
                session.finished = true
            } else { session.start(side, at: date) }
            let record = Activity(id: correcting ? (activity?.id ?? UUID()) : UUID(), familyID: family.id, childID: childID, occurredAt: date, createdAt: correcting ? (activity?.createdAt ?? .now) : .now, authorID: correcting ? (activity?.authorID ?? store.caregiverID) : store.caregiverID, source: activity?.source ?? "App", note: note, payload: .nursing(session))
            let commandID = UUID()
            try store.save(.activity(record), parentIDs: correcting ? parents : [], commandID: commandID)
            parents = [commandID]
            activity = record
            if manual { store.toast = String(localized: "Breastfeed saved for \(childName)"); dismiss() }
        } catch { self.error = error.localizedDescription }
    }
    private func update(_ change: (inout Nursing, Date) -> Void) {
        error = nil
        guard var record = activity, case .nursing(var session) = record.payload else { return }
        change(&session, .now)
        record.payload = .nursing(session)
        do {
            let commandID = UUID()
            try store.save(.activity(record), parentIDs: parents, commandID: commandID)
            parents = [commandID]; activity = record
        }
        catch { self.error = error.localizedDescription }
    }
}

struct NursingClock: View {
    @Environment(\.babyPalette) private var palette
    let nursing: Nursing
    let now: Date
    @ScaledMetric(relativeTo: .largeTitle) private var clockSize = 62
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "heart").font(.largeTitle).foregroundStyle(palette.accent)
            Text(LogAnalytics.duration(nursing.duration(at: now)))
                .font(.system(size: clockSize, weight: .light, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityLabel("Active feeding time, \(Int(nursing.duration(at: now) / 60)) minutes")
            Text(nursing.finished ? String(localized: "Session complete") : nursing.activeSide.map { String(localized: "\($0.title) side · Running") } ?? String(localized: "Paused"))
                .font(.headline).foregroundStyle(palette.accent)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 20)) : AnyLayout(HStackLayout(spacing: 36))
            layout {
                ForEach(BreastSide.allCases) { side in
                    VStack(spacing: 7) {
                        Text(side.title).foregroundStyle(.secondary)
                        Text(LogAnalytics.duration(nursing.duration(at: now, side: side))).font(.title3.weight(.medium)).monospacedDigit().lineLimit(1)
                    }.accessibilityElement(children: .combine)
                }
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 20).background(palette.surface, in: .rect(cornerRadius: 30))
    }
}
