import Foundation

enum WidgetQuickAction: String, CaseIterable, Codable, Sendable {
    case pee, poo, both, bottle

    var title: String {
        switch self { case .pee: String(localized: "Pee"); case .poo: String(localized: "Poo"); case .both: String(localized: "Both"); case .bottle: String(localized: "Bottle") }
    }
    var diaper: Diaper? {
        switch self {
        case .pee: Diaper(pee: true, poo: false)
        case .poo: Diaper(pee: false, poo: true)
        case .both: Diaper(pee: true, poo: true)
        case .bottle: nil
        }
    }
    static func action(for diaper: Diaper) -> Self? {
        switch (diaper.pee, diaper.poo) {
        case (true, false): .pee
        case (false, true): .poo
        case (true, true): .both
        default: nil
        }
    }
}

enum WidgetQuickLogSource: String, Codable, Sendable {
    case lockScreen = "Lock Screen"
    case homeScreen = "Home Screen"
}

struct WidgetQuickLogReceipt: Codable, Equatable, Sendable {
    static let undoDuration: TimeInterval = 60
    var recordID: UUID
    var createdAt: Date
    var undoUntil: Date { createdAt.addingTimeInterval(Self.undoDuration) }
    func canUndo(at date: Date) -> Bool { date >= createdAt && date < undoUntil }
}

enum WidgetQuickLogRules {
    static func isWidgetSource(_ source: String) -> Bool {
        WidgetQuickLogSource(rawValue: source) != nil
    }

    static func child(target: String, in snapshot: FamilySnapshot, ready: Bool,
                      canEdit: Bool, actorID: UUID) throws -> ChildProfile {
        guard ready else { throw LogError.message(String(localized: "Your family is still loading. Open Swaddle and try again.")) }
        guard canEdit else { throw LogError.message(String(localized: "This family is shared with view-only access.")) }
        let parts = target.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let familyID = UUID(uuidString: String(parts[0])),
              familyID == snapshot.family?.id, let childID = UUID(uuidString: String(parts[1])) else {
            throw LogError.message(String(localized: "Choose your child again in Edit Widget."))
        }
        guard snapshot.caregivers.contains(where: { $0.id == actorID }) else {
            throw LogError.message(String(localized: "Finish joining your family in Swaddle first."))
        }
        return try LogRules.child(childID, in: snapshot, ready: ready)
    }

    /// Only a pristine creation can be undone. An edit or conflict must be reviewed in the app.
    static func receipt(for record: ProjectedRecord, actorID: UUID) -> WidgetQuickLogReceipt? {
        guard !record.isDeleted, record.heads.count == 1, record.revision.id == record.id,
              record.revision.parentIDs.isEmpty, case .activity(let activity) = record.revision.value,
              isWidgetSource(activity.source), activity.authorID == actorID,
              case .diaper = activity.payload else { return nil }
        return WidgetQuickLogReceipt(recordID: record.id, createdAt: activity.createdAt)
    }
}
