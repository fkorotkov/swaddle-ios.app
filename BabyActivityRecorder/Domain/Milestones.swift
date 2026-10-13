import Foundation

enum MilestoneStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case seen, notYet, unsure, lost
    var id: Self { self }
    var title: String {
        switch self {
        case .seen: String(localized: "Seen it")
        case .notYet: String(localized: "Not yet")
        case .unsure: String(localized: "Not sure")
        case .lost: String(localized: "Used to do this")
        }
    }
    var symbol: String {
        switch self {
        case .seen: "checkmark.circle"
        case .notYet: "circle.dotted"
        case .unsure: "questionmark.circle"
        case .lost: "bubble.left.and.exclamationmark.bubble.right"
        }
    }
}

/// Each check-in is its own shared record. New observations never replace another
/// caregiver's account; corrections use the existing revision graph on this ID.
struct MilestoneObservation: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var familyID: UUID
    var childID: UUID
    var skillID: String
    var sourceVersion: String
    /// Retain the reviewed wording even if a later catalog revises it.
    var skillTitle: String
    var status: MilestoneStatus
    var firstNoticedAt: Date? = nil
    var note = ""
    var hasConcern = false
    var authorID: UUID
    var recordedAt = Date()
    var localizedTitle: String {
        guard let skill = MilestoneCatalog.skill(skillID), skill.title == skillTitle else { return skillTitle }
        return skill.localizedTitle
    }
}

enum MilestoneDomain: String, CaseIterable, Sendable {
    case social, language, cognitive, movement
    var title: String {
        switch self {
        case .social: String(localized: "Connecting")
        case .language: String(localized: "Sounds & words")
        case .cognitive: String(localized: "Learning & exploring")
        case .movement: String(localized: "Moving")
        }
    }
    var symbol: String {
        switch self {
        case .social: "face.smiling"
        case .language: "bubble.left.and.bubble.right"
        case .cognitive: "sparkle.magnifyingglass"
        case .movement: "figure.child"
        }
    }
}

struct MilestoneSkill: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let domain: MilestoneDomain
    let months: Int?
    let sourceVersion: String
    let sourceURL: String
    var motorWindow: ClosedRange<Double>? = nil
    var publisher: String { motorWindow == nil ? "CDC" : String(localized: "WHO") }
    /// UI translation does not rewrite frozen wording in existing check-ins.
    var localizedTitle: String {
        let translated = String(localized: String.LocalizationValue(id), table: "Milestones")
        return translated == id ? title : translated
    }
    var localizedSourceURL: String {
        CDCMilestoneLanguage.resolve(Bundle.main.preferredLocalizations.first ?? "en").sourceURL(for: self)
    }
}

enum MilestoneCatalog {
    static let checkpoints = [2, 4, 6, 9, 12, 15, 18, 24]
    static let cdcURL = "https://www.cdc.gov/act-early/milestones/index.html"
    static var localizedCDCURL: String {
        CDCMilestoneLanguage.resolve(Bundle.main.preferredLocalizations.first ?? "en").checklistURL
    }
    static let whoURL = "https://www.who.int/tools/child-growth-standards/standards/motor-development-milestones"
    static let ageGuidanceURL = "https://www.cdc.gov/wic-guide/php/administer-milestone-checklists/four-simple-steps.html"
    static let motorSkills: [MilestoneSkill] = [
        motor("sitting", "Sitting without support", 3.8...9.2),
        motor("standing-assisted", "Standing with assistance", 4.8...11.4),
        motor("crawling", "Hands-and-knees crawling", 5.2...13.5),
        motor("walking-assisted", "Walking with assistance", 6.0...13.7),
        motor("standing", "Standing alone", 6.9...16.9),
        motor("walking", "Walking alone", 8.2...17.6)
    ]
    static var all: [MilestoneSkill] { cdcSkills + motorSkills }
    static func skill(_ id: String) -> MilestoneSkill? { all.first { $0.id == id } }
    static func skills(at months: Int) -> [MilestoneSkill] { cdcSkills.filter { $0.months == months } }
    static func title(at months: Int) -> String { months == 12 ? String(localized: "1 year") : months == 24 ? String(localized: "2 years") : String(localized: "\(months) months") }
    static func subtitle(at months: Int) -> String {
        switch months {
        case 2: String(localized: "Sounds, smiles, and little movements")
        case 4: String(localized: "Finding their voice")
        case 6: String(localized: "More ways to discover the world")
        case 9: String(localized: "A world within reach")
        case 12: String(localized: "A year of little discoveries")
        case 15: String(localized: "Making connections")
        case 18: String(localized: "Exploring together")
        default: String(localized: "New words, new adventures")
        }
    }
    private static func motor(_ id: String, _ title: String, _ window: ClosedRange<Double>) -> MilestoneSkill {
        .init(id: "who-\(id)", title: title, domain: .movement, months: nil,
              sourceVersion: "who-motor-2006", sourceURL: whoURL, motorWindow: window)
    }
}

/// Calendar-month checkpoints, corrected for a birth before 37 weeks until the
/// second birthday. Upcoming chapters stay browsable, never become deadlines.
struct MilestoneAge: Equatable {
    let completedMonths: Int
    let isCorrected: Bool
    let beforeDueDate: Bool
    var current: Int? { completedMonths <= 24 ? MilestoneCatalog.checkpoints.last { $0 <= completedMonths } : nil }
    var upcoming: Int? { MilestoneCatalog.checkpoints.first { $0 > completedMonths } }
    var suggested: Int { current ?? upcoming ?? 24 }

    init?(child: ChildProfile, now: Date, calendar: Calendar) {
        guard let age = ChildAge(child: child, at: now, calendar: calendar),
              let birth = child.birthDate,
              let secondBirthday = calendar.date(byAdding: .year, value: 2, to: calendar.startOfDay(for: birth))
        else { return nil }
        isCorrected = age.correctedDays != nil && calendar.startOfDay(for: now) < secondBirthday
        let origin = isCorrected ? age.estimatedDueDate ?? birth : birth
        beforeDueDate = calendar.startOfDay(for: now) < calendar.startOfDay(for: origin)
        completedMonths = max(0, calendar.dateComponents([.month], from: calendar.startOfDay(for: origin), to: calendar.startOfDay(for: now)).month ?? 0)
    }
}

extension FamilySnapshot {
    var milestoneObservations: [MilestoneObservation] {
        let childIDs = Set(children.filter { $0.familyID == family?.id }.map(\.id))
        return records.compactMap { record in
            guard !record.isDeleted, case .milestone(let observation) = record.revision.value,
                  observation.familyID == family?.id, childIDs.contains(observation.childID)
            else { return nil }
            return observation
        }.sorted {
            $0.recordedAt == $1.recordedAt ? $0.id.uuidString < $1.id.uuidString : $0.recordedAt > $1.recordedAt
        }
    }
}

enum MilestoneRules {
    static func validate(_ observation: MilestoneObservation, in snapshot: FamilySnapshot, now: Date) throws {
        let child = try LogRules.child(observation.childID, in: snapshot)
        guard observation.familyID == child.familyID,
              !observation.skillID.isEmpty, !observation.sourceVersion.isEmpty,
              !observation.skillTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              snapshot.recordedCaregivers.contains(where: { $0.id == observation.authorID })
        else { throw LogError.message(String(localized: "This observation’s child, caregiver, or source is unavailable.")) }
        guard observation.recordedAt.timeIntervalSinceReferenceDate.isFinite,
              observation.recordedAt <= now, observation.note.count <= 2000
        else { throw LogError.message(String(localized: "Check the observation date and keep the note under 2,000 characters.")) }
        if let first = observation.firstNoticedAt {
            guard observation.status == .seen, first.timeIntervalSinceReferenceDate.isFinite,
                  first <= observation.recordedAt, child.birthDate.map({ first >= $0 }) ?? true
            else { throw LogError.message(String(localized: "The first-noticed date must be between birth and this check-in, for a skill you’ve seen.")) }
        }
    }
}
