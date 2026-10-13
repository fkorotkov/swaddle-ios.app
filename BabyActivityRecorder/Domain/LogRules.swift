import Foundation

enum LogError: LocalizedError, Equatable {
    case message(String)
    case needsChild
    case needsMother
    var errorDescription: String? {
        switch self {
        case .message(let message): message
        case .needsChild: String(localized: "Which child would you like to record this for?")
        case .needsMother: String(localized: "Choose the mother this pumping session belongs to.")
        }
    }
}

enum LogDestination: Equatable {
    case today(childID: UUID)
    case bottle(childID: UUID)
    case family

    static func resolve(_ url: URL, in snapshot: FamilySnapshot, ready: Bool) throws -> LogDestination {
        guard url.scheme == "littlelog" else { throw LogError.message(String(localized: "This link isn’t for Swaddle.")) }
        if url.host == "family" { return .family }
        guard ready else { throw LogError.message(String(localized: "Your family is still loading. Please open the widget again shortly.")) }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard ["today", "bottle"].contains(url.host ?? ""),
              let familyID = items.first(where: { $0.name == "family" })?.value.flatMap(UUID.init(uuidString:)),
              familyID == snapshot.family?.id,
              let childID = items.first(where: { $0.name == "child" })?.value.flatMap(UUID.init(uuidString:)) else {
            throw LogError.message(String(localized: "This widget’s family is no longer available. Choose a child in Edit Widget."))
        }
        let child = try LogRules.child(childID, in: snapshot, ready: ready)
        return url.host == "bottle" ? .bottle(childID: child.id) : .today(childID: child.id)
    }
}

enum LogRules {
    /// Compare feeding segments, excluding pauses and sessions belonging to other children.
    static func overlappingNursing(in activities: [Activity], childID: UUID, now: Date) -> Set<UUID> {
        let segments = activities.flatMap { activity -> [(id: UUID, start: Date, end: Date)] in
            guard activity.childID == childID, case .nursing(let session) = activity.payload else { return [] }
            return session.segments.map { (activity.id, $0.start, $0.end ?? now) }.filter { $0.2 > $0.1 }
        }.sorted { $0.start < $1.start }
        var active: [(id: UUID, start: Date, end: Date)] = []
        var result: Set<UUID> = []
        for segment in segments {
            active.removeAll { $0.end <= segment.start }
            for other in active where other.id != segment.id { result.insert(other.id); result.insert(segment.id) }
            active.append(segment)
        }
        return result
    }
    static func child(_ explicit: UUID?, in snapshot: FamilySnapshot, ready: Bool = true) throws -> ChildProfile {
        guard ready else { throw LogError.message(String(localized: "Your family is still loading. Please try again shortly.")) }
        if let explicit {
            guard let child = snapshot.children.first(where: { $0.id == explicit }) else {
                throw LogError.message(String(localized: "This child is no longer available. Choose a child in Settings."))
            }
            return child
        }
        guard !snapshot.children.isEmpty else { throw LogError.message(String(localized: "Add a child in Swaddle first.")) }
        guard snapshot.children.count == 1 else { throw LogError.needsChild }
        return snapshot.children[0]
    }
    static func mother(_ explicit: UUID?, in snapshot: FamilySnapshot) throws -> Caregiver {
        let mothers = snapshot.caregivers.filter(\.isMother)
        if let explicit {
            guard
                let person = mothers.first(where: {
                    $0.id == snapshot.canonicalCaregiverID(explicit)
                })
            else { throw LogError.message(String(localized: "This mother is no longer available.")) }
            return person
        }
        guard !mothers.isEmpty else { throw LogError.message(String(localized: "Add a mother’s profile in Settings to log pumping.")) }
        guard mothers.count == 1 else { throw LogError.needsMother }
        return mothers[0]
    }
    static func validate(_ value: RecordValue, in snapshot: FamilySnapshot, now: Date) throws {
        guard value.familyID == snapshot.family?.id else { throw LogError.message(String(localized: "This record belongs to a different family.")) }
        switch value {
        case .milestone(let observation):
            try MilestoneRules.validate(observation, in: snapshot, now: now)
        case .child(let child):
            guard !child.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LogError.message(String(localized: "Enter a child’s name.")) }
            try child.validateBirthDetails(now: now)
        case .caregiver(let person):
            guard !person.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LogError.message(String(localized: "Enter a caregiver’s name.")) }
            guard person.mergedIntoID == nil else {
                throw LogError.message(String(localized: "Use Merge caregiver profiles to combine profiles."))
            }
        case .activity(let activity):
            _ = try child(activity.childID, in: snapshot)
            try past(activity.occurredAt, now: now)
            switch activity.payload {
            case .diaper(let d):
                guard d.pee || d.poo else { throw LogError.message(String(localized: "Select pee, poo, or both.")) }
            case .bottle(let b):
                try b.validate()
            case .nursing(let n):
                guard
                    snapshot.caregivers.contains(where: {
                        $0.id == snapshot.canonicalCaregiverID(n.caregiverID)
                    })
                else { throw LogError.message(String(localized: "Choose a feeding caregiver.")) }
                guard !n.segments.isEmpty else { throw LogError.message(String(localized: "Start a timer or enter a duration.")) }
                var priorEnd: Date?
                for (index, segment) in n.segments.enumerated() {
                    try past(segment.start, now: now)
                    guard segment.start >= activity.occurredAt,
                          priorEnd.map({ segment.start >= $0 }) ?? true,
                          segment.end.map({ $0 >= segment.start && $0 <= now }) ?? (index == n.segments.count - 1 && !n.finished)
                    else { throw LogError.message(String(localized: "Check the feeding session’s start and end times.")) }
                    priorEnd = segment.end
                }
                if n.finished && n.duration(at: now) <= 0 { throw LogError.message(String(localized: "Enter a feeding duration greater than zero.")) }
            case .weight(let grams, _):
                guard grams > 0, !grams.isNaN else { throw LogError.message(String(localized: "Enter a weight greater than zero.")) }
            case .length(let centimeters, _, _), .headCircumference(let centimeters, _):
                guard !centimeters.isNaN, centimeters > 0, centimeters.double.isFinite else {
                    throw LogError.message(String(localized: "Enter a measurement greater than zero."))
                }
            case .temperature(let celsius, _, _):
                guard !celsius.isNaN, celsius > Decimal(string: "-273.15")! else { throw LogError.message(String(localized: "Enter a valid temperature.")) }
            case .careNote:
                guard !activity.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LogError.message(String(localized: "Enter a note.")) }
            }
        case .pumping(let pump):
            _ = try mother(pump.motherID, in: snapshot)
            try past(pump.occurredAt, now: now)
            try volumes([pump.totalML])
            if pump.leftML != nil || pump.rightML != nil {
                guard let l = pump.leftML, let r = pump.rightML, l >= 0, r >= 0, l + r == pump.totalML else {
                    throw LogError.message(String(localized: "Left and right volumes must add up to the total."))
                }
            }
            if let duration = pump.minutes, duration <= 0 || duration.isNaN { throw LogError.message(String(localized: "Enter a duration greater than zero.")) }
        }
    }
    static func past(_ date: Date, now: Date) throws {
        guard date <= now else { throw LogError.message(String(localized: "Choose a time in the past or now.")) }
    }
    static func volumes(_ amounts: [Decimal]) throws {
        guard amounts.allSatisfy({ !$0.isNaN && $0 >= 0 }), amounts.reduce(0, +) > 0 else {
            throw LogError.message(String(localized: "Enter a volume greater than zero. Amounts can’t be negative."))
        }
    }
}

struct ActivitySummary: Equatable, Sendable {
    var milkML: Decimal = 0
    var formulaML: Decimal = 0
    var unknownML: Decimal = 0
    var bottles = 0
    var peeOnly = 0
    var pooOnly = 0
    var both = 0
    var nursingSeconds: TimeInterval = 0
    var nursingSessions = 0
    var wet: Int { peeOnly + both }
    var soiled: Int { pooOnly + both }
    var changes: Int { peeOnly + pooOnly + both }
    var totalML: Decimal { milkML + formulaML + unknownML }
    init(activities: [Activity] = [], childID: UUID? = nil, start: Date = .distantPast, end: Date = .now) {
        for item in activities where item.childID == childID && item.occurredAt > start && item.occurredAt <= end {
            switch item.payload {
            case .bottle(let b): milkML += b.milkML; formulaML += b.formulaML; unknownML += b.unknownML; bottles += 1
            case .diaper(let d):
                if d.pee && d.poo { both += 1 } else if d.pee { peeOnly += 1 } else { pooOnly += 1 }
            case .nursing(let n) where n.finished: nursingSeconds += n.duration(at: end); nursingSessions += 1
            default: break
            }
        }
    }
}

struct DailySummary: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var summary: ActivitySummary
    var isPartial: Bool
}

enum LogAnalytics {
    static func recordedMinutes(_ seconds: TimeInterval) -> String {
        let unit = String(localized: "min")
        return seconds > 0 && seconds < 60 ? "<1 \(unit)" : "\(Int(seconds / 60).formatted()) \(unit)"
    }
    static func days(activities: [Activity], childID: UUID, count: Int, now: Date, timeZone: TimeZone) -> [DailySummary] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            // Calendar buckets are [start, end), unlike the elapsed rolling window.
            let records = activities.filter { $0.occurredAt >= day && $0.occurredAt < end }
            return DailySummary(date: day, summary: ActivitySummary(activities: records, childID: childID, end: now), isPartial: offset == 0)
        }
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
