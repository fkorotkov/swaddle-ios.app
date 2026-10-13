import SwiftUI

/// A check-in belongs to the selected skill, independent of its display column.
@Observable final class MilestoneCheckInDraft {
    let route: MilestoneCheckInRoute
    let parents: Set<UUID>?
    let commandID = UUID()
    var status: MilestoneStatus?
    var note: String
    var noteExpanded: Bool
    var includeDate: Bool
    var firstDate: Date
    var concern: Bool

    init(route: MilestoneCheckInRoute, snapshot: FamilySnapshot, initialStatus: MilestoneStatus? = nil) {
        self.route = route
        status = route.observation?.status ?? initialStatus
        note = route.observation?.note ?? ""
        noteExpanded = !(route.observation?.note.isEmpty ?? true)
        includeDate = route.observation?.firstNoticedAt != nil || initialStatus == .seen
        firstDate = route.observation?.firstNoticedAt ?? route.observation?.recordedAt ?? .now
        concern = route.observation?.hasConcern ?? false
        parents = route.observation.map { Set(snapshot.record($0.id)?.heads.map(\.id) ?? []) }
    }

    var isDirty: Bool {
        status != route.observation?.status || note != (route.observation?.note ?? "")
            || concern != (route.observation?.hasConcern ?? false)
            || (status == .seen && includeDate ? firstDate : nil) != route.observation?.firstNoticedAt
    }
}
