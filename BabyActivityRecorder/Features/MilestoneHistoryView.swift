import SwiftUI

struct MilestoneHistoryView: View {
    let store: LogStore
    let child: ChildProfile
    @State private var route: MilestoneCheckInRoute?
    @State private var removing: MilestoneObservation?
    @State private var error: String?
    @State private var savedID: UUID?
    private var observations: [MilestoneObservation] {
        store.snapshot.milestoneObservations.filter { $0.childID == child.id }
    }
    var body: some View {
        List {
            if observations.isEmpty {
                ContentUnavailableView("A story still unfolding", systemImage: "leaf", description: Text("Saved observations for \(child.name) will appear here."))
            }
            ForEach(observations) { observation in
                observationRow(observation)
            }
        }.navigationTitle("Family observations").navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden).background(LogStyle.canvas)
            .safeAreaPadding(.bottom, 100)
            .sheet(item: $route) { MilestoneCheckInView(store: store, route: $0) { id in
                withAnimation(.easeOut(duration: 0.18)) { savedID = id }
            } }
            .overlay(alignment: .bottom) {
                if savedID != nil {
                    SaveConfirmation(message: String(localized: "Observation updated"), undoID: nil, undo: {}) { savedID = nil }
                        .padding(16).transition(.opacity)
                }
            }
            .sensoryFeedback(.success, trigger: savedID)
            .task(id: savedID) {
                guard savedID != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.18)) { savedID = nil }
            }
            .confirmationDialog("Delete this observation?", item: $removing, titleVisibility: .visible) { observation in
                Button("Delete observation", role: .destructive) {
                    deleteObservation(observation)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in Text("This updates the shared family log. You can restore it in Settings → Review edits & deleted entries.") }
            .alert("Couldn’t delete observation", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
    }

    private func deleteObservation(_ observation: MilestoneObservation) {
        do {
            if let record = store.snapshot.record(observation.id) { try store.delete(record) }
            removing = nil
        } catch { self.error = error.localizedDescription }
    }

    private func observationRow(_ observation: MilestoneObservation) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(observation.localizedTitle).font(LogStyle.heading(.headline))
            MilestoneObservationSummary(observation: observation, snapshot: store.snapshot)
            if let skill = MilestoneCatalog.skill(observation.skillID) {
                Button(store.canEdit ? String(localized: "Edit observation") : String(localized: "View observation")) {
                    route = MilestoneCheckInRoute(child: child, skill: skill, observation: observation)
                }.frame(minHeight: 44)
            }
            if store.canEdit {
                Button(role: .destructive) { removing = observation } label: {
                    Label("Delete observation", systemImage: "trash").frame(minHeight: 44)
                }.buttonStyle(.borderless)
            }
        }.padding(.vertical, 8)
    }
}
