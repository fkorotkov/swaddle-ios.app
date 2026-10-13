import Foundation

/// Calendar birthdays, separate from corrected age used by developmental check-ins.
struct AgeCelebration: Identifiable, Equatable, Sendable {
    let id: String
    let childID: UUID
    let childName: String
    let week: Int
    let nextCheckpoint: Int?

    init?(child: ChildProfile, at now: Date, calendar: Calendar) {
        guard let birth = child.birthDate,
              let age = ChildAge(child: child, at: now, calendar: calendar),
              [7, 14, 21, 28].contains(age.chronologicalDays) else { return nil }
        childID = child.id
        childName = child.name
        week = age.chronologicalDays / 7
        // Keep the receipt stable across time-zone, name, and appearance changes.
        id = "\(child.familyID).\(child.id).\(birth.timeIntervalSince1970.bitPattern).week\(week)"
        nextCheckpoint = week == 4
            ? MilestoneAge(child: child, now: now, calendar: calendar)?.upcoming : nil
    }

    var receiptKey: String { "careCelebration.age.v1.\(id)" }
    var title: String { String(localized: "\(week) \(week == 1 ? String(localized: "week") : String(localized: "weeks")) of \(childName).") }
    var message: String {
        switch week {
        case 1: String(localized: "A whole week of getting to know you.")
        case 2: String(localized: "Your little story is two weeks old.")
        case 3: String(localized: "Three weeks of life together.")
        default: String(localized: "A little birthday. So many little moments.")
        }
    }
}

/// A transient acknowledgment of a new, locally recorded session, never a goal.
struct PumpingPersonalRecord: Identifiable, Equatable, Sendable {
    let id: UUID
    let caregiverID: UUID
    let totalML: Decimal
    let previousML: Decimal

    static func detect(
        newSession: PumpSession, in snapshot: FamilySnapshot, actorID: UUID, at now: Date
    ) -> Self? {
        let pumperID = snapshot.canonicalCaregiverID(newSession.motherID)
        let actor = snapshot.canonicalCaregiverID(actorID)
        guard snapshot.family?.id == newSession.familyID,
              snapshot.record(newSession.id) == nil,
              newSession.importIdentity == nil,
              ["App", "Siri", "Siri / Shortcuts"].contains(newSession.source),
              pumperID == actor,
              snapshot.canonicalCaregiverID(newSession.authorID) == actor,
              snapshot.caregivers.contains(where: { $0.id == pumperID && $0.isMother }),
              newSession.totalML > 0, !newSession.totalML.isNaN,
              newSession.occurredAt.timeIntervalSince1970.isFinite,
              newSession.occurredAt <= now else { return nil }

        let previous = snapshot.pumps.filter {
            $0.familyID == newSession.familyID && $0.motherID == pumperID
                && $0.totalML > 0 && !$0.totalML.isNaN && $0.occurredAt <= now
        }.map(\.totalML).max()
        guard let previous, newSession.totalML > previous else { return nil }
        return Self(id: newSession.id, caregiverID: pumperID,
                    totalML: newSession.totalML, previousML: previous)
    }
}
