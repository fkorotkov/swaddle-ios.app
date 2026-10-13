import Foundation

enum ReportPeriod: String, CaseIterable, Sendable {
    case last24Hours, today, yesterday
    var title: String {
        switch self { case .last24Hours: String(localized: "Last 24 hours"); case .today: String(localized: "Today"); case .yesterday: String(localized: "Yesterday") }
    }
    func window(now: Date, timeZone: TimeZone) -> (start: Date, end: Date) {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        switch self {
        case .last24Hours: return (now.addingTimeInterval(-86400), now)
        case .today: return (today.addingTimeInterval(-0.001), now)
        case .yesterday:
            let prior = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            return (prior.addingTimeInterval(-0.001), today.addingTimeInterval(-0.001))
        }
    }
}

struct FeedingReport: Sendable {
    let childName: String
    let period: ReportPeriod
    let summary: ActivitySummary
    let asOf: Date
    let timeZoneIdentifier: String
    init(child: ChildProfile, period: ReportPeriod, snapshot: FamilySnapshot, now: Date) {
        childName = child.name; self.period = period; asOf = now
        let zone = TimeZone(identifier: snapshot.family?.timeZoneIdentifier ?? "") ?? .current
        timeZoneIdentifier = zone.identifier
        let window = period.window(now: now, timeZone: zone)
        summary = ActivitySummary(activities: snapshot.activities, childID: child.id, start: window.start, end: window.end)
    }
    func spoken(unit: VolumeUnit) -> String {
        let intro = String(localized: "For \(childName), \(period.title.lowercased()): ")
        let composition = summary.milkML + summary.formulaML > 0 ? String(localized: " \(unit.quantity(summary.milkML)) breast milk and \(unit.quantity(summary.formulaML)) formula.") : ""
        let bottleCount = String(localized: "\(summary.bottles) feeds")
        let bottles = summary.bottles == 0 ? String(localized: "No bottle feeds recorded.") : String(localized: "\(unit.quantity(summary.totalML)) recorded across \(bottleCount).") + composition
        let duration = Duration.seconds(summary.nursingSeconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        let nursingCount = String(localized: "\(summary.nursingSessions) sessions")
        let nursing = summary.nursingSessions == 0 ? "" : String(localized: " Also breastfeeding: \(nursingCount), \(duration) recorded. Breastfeeding time isn’t converted to volume.")
        let unknown = summary.unknownML > 0 ? String(localized: " Of that total, \(unit.quantity(summary.unknownML)) has an unrecorded milk/formula split.") : ""
        return intro + bottles + unknown + nursing
    }
}
