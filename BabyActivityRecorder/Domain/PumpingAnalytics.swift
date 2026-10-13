import Foundation

/// The signed-in caregiver's expressed volume in the dashboard's reporting window.
/// Uses projected sessions so merges, edits, and deletions match family history.
struct PumpingSummary: Equatable, Sendable {
    let caregiver: Caregiver
    let totalML: Decimal
    let sessions: Int

    init?(snapshot: FamilySnapshot, caregiverID: UUID, start: Date, end: Date) {
        let resolvedID = snapshot.canonicalCaregiverID(caregiverID)
        guard let family = snapshot.family,
              let caregiver = snapshot.caregivers.first(where: {
                  $0.id == resolvedID && $0.familyID == family.id && $0.isMother
              }) else { return nil }
        self.caregiver = caregiver
        let entries = snapshot.pumps.filter {
            $0.familyID == family.id && $0.motherID == caregiver.id
                && $0.occurredAt > start && $0.occurredAt <= end
        }
        totalML = entries.reduce(0) { $0 + $1.totalML }
        sessions = entries.count
    }
}

struct DailyPumpingSummary: Identifiable, Equatable, Sendable {
    var id: Date { date }
    let date: Date
    let totalML: Decimal
    let sessions: Int
}

extension LogAnalytics {
    /// Pumping belongs to a caregiver, independent of the selected child.
    /// The caller supplies projected sessions, which already exclude deletions.
    static func pumpingDays(sessions: [PumpSession], familyID: UUID, motherID: UUID,
                            count: Int, now: Date, timeZone: TimeZone) -> [DailyPumpingSummary] {
        guard count > 0 else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let lastDay = calendar.startOfDay(for: now)
        guard let firstDay = calendar.date(byAdding: .day, value: 1 - count, to: lastDay) else { return [] }
        let records = sessions.filter {
            $0.familyID == familyID && $0.motherID == motherID && $0.occurredAt >= firstDay && $0.occurredAt <= now
        }
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.occurredAt) }
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }
            let day = grouped[date, default: []]
            // totalML already includes any left/right components. Count each session once.
            return DailyPumpingSummary(date: date, totalML: day.reduce(0) { $0 + $1.totalML }, sessions: day.count)
        }
    }
}
