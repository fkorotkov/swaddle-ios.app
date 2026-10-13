import Foundation

struct CachedChild: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var familyID: UUID
    var name: String
    var activities: [Activity]
    var gender: ChildGender? = nil
    var quickLogs: [String: WidgetQuickLogReceipt]? = nil
}
struct WidgetSnapshot: Codable, Equatable, Sendable {
    var asOf: Date
    var children: [CachedChild]
    var canRecord: Bool? = nil
    var actorID: UUID? = nil
    /// Family pumping is shared across children. Nil means an older app has not
    /// published this part of the cache yet; it must not be presented as zero.
    var pumps: [CachedPumpSession]? = nil

    static func capture(_ snapshot: FamilySnapshot, actorID: UUID?, canRecord: Bool, at now: Date) -> Self {
        let start = now.addingTimeInterval(-86400)
        let children = snapshot.children.map { child in
            var receipts: [String: WidgetQuickLogReceipt] = [:]
            if let actorID {
                for record in snapshot.records {
                    guard case .activity(let activity) = record.revision.value,
                          activity.familyID == child.familyID, activity.childID == child.id,
                          case .diaper(let diaper) = activity.payload,
                          let action = WidgetQuickAction.action(for: diaper),
                          let receipt = WidgetQuickLogRules.receipt(for: record, actorID: actorID),
                          receipt.canUndo(at: now) else { continue }
                    if receipt.createdAt > (receipts[action.rawValue]?.createdAt ?? .distantPast) {
                        receipts[action.rawValue] = receipt
                    }
                }
            }
            return CachedChild(id: child.id, familyID: child.familyID, name: child.name,
                activities: snapshot.activities.filter {
                    $0.familyID == child.familyID && $0.childID == child.id && $0.occurredAt > start
                }, gender: child.paletteGender, quickLogs: receipts)
        }
        let pumps = snapshot.pumps.filter {
            $0.familyID == snapshot.family?.id && $0.occurredAt > start
        }.map { CachedPumpSession(id: $0.id, familyID: $0.familyID, occurredAt: $0.occurredAt, totalML: $0.totalML) }
        return Self(asOf: now, children: children, canRecord: canRecord, actorID: actorID, pumps: pumps)
    }
}

/// Only the fields needed for a rolling total belong in the widget cache.
struct CachedPumpSession: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let familyID: UUID
    let occurredAt: Date
    let totalML: Decimal
}

struct WidgetCareSummary: Equatable, Sendable {
    let activity: ActivitySummary
    let pumpedML: Decimal?
    let pumpingSessions: Int?

    init(child: CachedChild, pumps: [CachedPumpSession]?, at date: Date) {
        let start = date.addingTimeInterval(-86400)
        activity = ActivitySummary(activities: child.activities.filter { $0.familyID == child.familyID },
            childID: child.id, start: start, end: date)
        let sessions = pumps?.filter {
            $0.familyID == child.familyID && $0.occurredAt > start && $0.occurredAt <= date
        }
        pumpedML = sessions?.reduce(Decimal.zero) { $0 + $1.totalML }
        pumpingSessions = sessions?.count
    }
}

enum WidgetCareTimeline {
    /// Pre-render rolling totals locally, including exact expirations. WidgetKit
    /// controls reload timing; no network request or repeating view timer is used.
    static func dates(child: CachedChild?, pumps: [CachedPumpSession]?, from now: Date) -> [Date] {
        let end = now.addingTimeInterval(3600)
        var dates = Set((0...12).map { now.addingTimeInterval(Double($0) * 300) })
        if let child {
            let events = child.activities.filter { $0.childID == child.id && $0.familyID == child.familyID }.map(\.occurredAt)
                + (pumps ?? []).filter { $0.familyID == child.familyID }.map(\.occurredAt)
            for date in events {
                if date > now && date <= end { dates.insert(date) }
                let expiration = date.addingTimeInterval(86400)
                if expiration > now && expiration <= end { dates.insert(expiration) }
            }
            for receipt in child.quickLogs?.values ?? Dictionary<String, WidgetQuickLogReceipt>().values {
                if receipt.undoUntil > now && receipt.undoUntil <= end { dates.insert(receipt.undoUntil) }
            }
        }
        return dates.sorted()
    }
}
