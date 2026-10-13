import Foundation

nonisolated enum VolumeUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case ml, oz
    var id: String { rawValue }
    var label: String { self == .ml ? String(localized: "mL") : String(localized: "oz") }
    // The app's convenient bottle convention. Never rewrite previously stored mL.
    static let millilitersPerOunce: Decimal = 30
    func toML(_ value: Decimal) -> Decimal { self == .ml ? value : value * Self.millilitersPerOunce }
    func fromML(_ value: Decimal) -> Decimal { self == .ml ? value : value / Self.millilitersPerOunce }
    func string(_ ml: Decimal) -> String {
        fromML(ml).formatted(.number.precision(.fractionLength(0...(self == .ml ? 1 : 2))))
    }
    func quantity(_ ml: Decimal) -> String { "\(string(ml)) \(label)" }
}

enum ActivityKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bottle, diaper, breastfeeding, weight, length, headCircumference, temperature, careNote
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bottle: String(localized: "Bottle")
        case .diaper: String(localized: "Diaper")
        case .breastfeeding: String(localized: "Breastfeed")
        case .weight: String(localized: "Weight")
        case .length: String(localized: "Length / height")
        case .headCircumference: String(localized: "Head circumference")
        case .temperature: String(localized: "Temperature")
        case .careNote: String(localized: "Care note")
        }
    }
    var symbol: String {
        switch self {
        case .bottle: "waterbottle.fill"
        case .diaper: "drop.fill"
        case .breastfeeding: "heart.fill"
        case .weight: "scalemass.fill"
        case .length: "ruler"
        case .headCircumference: "person.crop.circle"
        case .temperature: "thermometer.medium"
        case .careNote: "note.text"
        }
    }
}

enum BreastSide: String, Codable, CaseIterable, Identifiable, Sendable {
    case left, right
    var id: String { rawValue }
    var title: String { self == .left ? String(localized: "Left") : String(localized: "Right") }
    var other: Self { self == .left ? .right : .left }
}

enum ChildGender: String, Codable, CaseIterable, Identifiable, Sendable {
    case boy, girl
    var id: String { rawValue }
    var title: String { self == .boy ? String(localized: "Boy") : String(localized: "Girl") }
}

/// An optional override of the reference suggested by the child's profile.
enum GrowthReferenceSex: String, Codable, CaseIterable, Identifiable, Sendable {
    case male, female
    var id: String { rawValue }
    var title: String { self == .male ? String(localized: "Boys") : String(localized: "Girls") }
}

enum ChildColorTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case sage, blue, rose
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sage: String(localized: "Sage")
        case .blue: String(localized: "Blue")
        case .rose: String(localized: "Rose")
        }
    }
}

struct ChildProfile: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var familyID: UUID
    var name: String
    var birthDate: Date?
    var gender: ChildGender? = nil
    /// Completed gestational days at birth. Nil keeps older profiles unchanged.
    var gestationalAgeAtBirthDays: Int? = nil
    var growthReferenceSex: GrowthReferenceSex? = nil
    /// Nil follows the profile's default colors. Never used for growth calculations.
    var colorTheme: ChildColorTheme? = nil


    var defaultGrowthReferenceSex: GrowthReferenceSex? {
        gender.map { $0 == .boy ? .male : .female }
    }

    var effectiveGrowthReferenceSex: GrowthReferenceSex? {
        growthReferenceSex ?? defaultGrowthReferenceSex
    }

    /// Appearance input for the app and the existing widget color cache.
    var paletteGender: ChildGender? {
        switch colorTheme {
        case .blue: .boy
        case .rose: .girl
        case .sage: nil
        case nil: gender
        }
    }
}

struct Caregiver: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var familyID: UUID
    var name: String
    var isMother: Bool = false
    var cloudIdentity: String? = nil
    var invitation: CaregiverInvitation? = nil
    /// A reversible alias on a deleted duplicate; original care records keep their IDs.
    var mergedIntoID: UUID? = nil
    var sex: CaregiverSex? = nil

}

struct Family: Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var timeZoneIdentifier: String
    var ownerID: UUID
}

struct Bottle: Codable, Equatable, Sendable {
    var milkML: Decimal
    var formulaML: Decimal
    var unit: VolumeUnit
    /// A known total whose milk/formula split was not recorded. Nil in older records.
    var unclassifiedML: Decimal? = nil
    var unknownML: Decimal { unclassifiedML ?? 0 }
    var totalML: Decimal { milkML + formulaML + unknownML }

    func validate() throws {
        try LogRules.volumes([milkML, formulaML, unknownML])
        guard unknownML == 0 || (milkML == 0 && formulaML == 0) else {
            throw LogError.message(String(localized: "Enter either the milk/formula amounts or a total with an unknown split."))
        }
    }
}

struct Diaper: Codable, Equatable, Sendable {
    var pee: Bool
    var poo: Bool
    var title: String { pee && poo ? String(localized: "Pee + poo") : pee ? String(localized: "Pee only") : String(localized: "Poo only") }
}

struct NursingSegment: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var side: BreastSide
    var start: Date
    var end: Date?
    func duration(at date: Date) -> TimeInterval { max(0, (end ?? date).timeIntervalSince(start)) }
}

struct Nursing: Codable, Equatable, Sendable {
    var caregiverID: UUID
    var segments: [NursingSegment] = []
    var finished = false
    var activeSide: BreastSide? { segments.last.flatMap { $0.end == nil ? $0.side : nil } }
    func duration(at date: Date, side: BreastSide? = nil) -> TimeInterval {
        segments.filter { side == nil || $0.side == side }.reduce(0) { $0 + $1.duration(at: date) }
    }
    mutating func pause(at date: Date) {
        guard let last = segments.indices.last, segments[last].end == nil else { return }
        segments[last].end = max(segments[last].start, date)
    }
    mutating func start(_ side: BreastSide, at date: Date) {
        pause(at: date)
        segments.append(NursingSegment(side: side, start: date))
    }
    mutating func resume(on side: BreastSide? = nil, at date: Date) {
        start(side ?? segments.last?.side ?? .left, at: date)
    }
    mutating func switchSide(at date: Date) {
        start((segments.last?.side ?? .left).other, at: date)
    }
}

enum ActivityPayload: Codable, Equatable, Sendable {
    case bottle(Bottle)
    case diaper(Diaper)
    case nursing(Nursing)
    case weight(grams: Decimal, unit: String)
    case length(centimeters: Decimal, unit: LengthUnit, position: LengthMeasurementPosition)
    case headCircumference(centimeters: Decimal, unit: LengthUnit)
    case temperature(celsius: Decimal, unit: String, method: String)
    case careNote
    var kind: ActivityKind {
        switch self {
        case .bottle: .bottle
        case .diaper: .diaper
        case .nursing: .breastfeeding
        case .weight: .weight
        case .length: .length
        case .headCircumference: .headCircumference
        case .temperature: .temperature
        case .careNote: .careNote
        }
    }
    var isComplete: Bool { if case .nursing(let n) = self { return n.finished }; return true }
}

struct ImportIdentity: Codable, Equatable, Hashable, Sendable {
    var source: String
    var id: String
}

struct Activity: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var familyID: UUID
    var childID: UUID
    var occurredAt: Date
    var timeZoneIdentifier = TimeZone.current.identifier
    var createdAt = Date()
    var authorID: UUID
    var source = "App"
    var note = ""
    var payload: ActivityPayload
    /// Optional export identity, scoped to this family and child. Absent in older records.
    var importIdentity: ImportIdentity? = nil
}

struct PumpSession: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var familyID: UUID
    var motherID: UUID
    var occurredAt: Date
    var createdAt = Date()
    var authorID: UUID
    var source = "App"
    var totalML: Decimal
    var leftML: Decimal?
    var rightML: Decimal?
    var unit: VolumeUnit
    var minutes: Decimal?
    var note = ""
    var importIdentity: ImportIdentity? = nil
    var timeZoneIdentifier: String? = nil
}

/// Versioned, typed payloads. Unknown versions fail closed instead of replacing existing data.
struct RecordEnvelope: Codable, Equatable, Sendable {
    static let supportedVersions = 1...6
    var version = 1
    var value: RecordValue
    init(value: RecordValue) {
        self.value = value
        // Older apps must request an update, never silently display an unknown total as zero.
        if case .activity(let activity) = value, case .bottle(let bottle) = activity.payload, bottle.unknownML > 0 {
            version = 2
        }
        // Earlier clients must update before interpreting combined caregiver history.
        if case .caregiver(let person) = value, person.mergedIntoID != nil { version = 3 }
        if case .milestone = value { version = 4 }
        if case .activity(let activity) = value,
           [.length, .headCircumference].contains(activity.payload.kind) { version = 5 }
        // Older editors would drop the optional caregiver sex on save.
        // Version 6 remains readable: its retired ethnicity/appearance keys
        // are ignored by Codable and omitted from new profile revisions.
        if case .caregiver(let person) = value, person.sex != nil { version = 6 }
    }
}

enum RecordValue: Codable, Equatable, Sendable {
    case child(ChildProfile), caregiver(Caregiver), activity(Activity), pumping(PumpSession), milestone(MilestoneObservation)
    var id: UUID {
        switch self {
        case .child(let v): v.id
        case .caregiver(let v): v.id
        case .activity(let v): v.id
        case .pumping(let v): v.id
        case .milestone(let v): v.id
        }
    }
    var familyID: UUID {
        switch self {
        case .child(let v): v.familyID
        case .caregiver(let v): v.familyID
        case .activity(let v): v.familyID
        case .pumping(let v): v.familyID
        case .milestone(let v): v.familyID
        }
    }
}

struct RecordRevision: Identifiable, Equatable, Sendable {
    var id: UUID
    var recordID: UUID
    var parentIDs: Set<UUID>
    var value: RecordValue
    var date: Date
    var editorID: UUID
    var deleted: Bool

    fileprivate var keepsLinkedCaregiver: Bool {
        guard !deleted, case .caregiver(let person) = value else { return false }
        return person.cloudIdentity != nil
    }
}

struct ProjectedRecord: Identifiable, Equatable, Sendable {
    var id: UUID { revision.recordID }
    var revision: RecordRevision
    var heads: [RecordRevision]
    var hasConflict: Bool { heads.count > 1 }
    var isDeleted: Bool {
        // An offline deletion must not hide an account linked concurrently on
        // another device. Retain that profile while the conflict is reviewed.
        !heads.contains(where: \.keepsLinkedCaregiver) && heads.contains(where: \.deleted)
    }
}

/// Pumping belongs to the family caregiver, not to a child's consumed intake.
enum RecentCareEntry: Identifiable, Equatable, Sendable {
    case activity(Activity)
    case pumping(PumpSession)

    var id: UUID {
        switch self {
        case .activity(let activity): activity.id
        case .pumping(let pump): pump.id
        }
    }

    var occurredAt: Date {
        switch self {
        case .activity(let activity): activity.occurredAt
        case .pumping(let pump): pump.occurredAt
        }
    }
}

enum RevisionProjection {
    static func project(_ revisions: [RecordRevision]) -> [ProjectedRecord] {
        Dictionary(grouping: revisions, by: \.recordID).values.compactMap { all in
            let parentIDs = all.reduce(into: Set<UUID>()) { $0.formUnion($1.parentIDs) }
            let heads = all.filter { !parentIDs.contains($0.id) }.sorted {
                if $0.keepsLinkedCaregiver != $1.keepsLinkedCaregiver { return $0.keepsLinkedCaregiver }
                if $0.deleted != $1.deleted { return $0.deleted }
                if $0.date != $1.date { return $0.date > $1.date }
                return $0.id.uuidString < $1.id.uuidString
            }
            guard let winner = heads.first else { return nil }
            return ProjectedRecord(revision: winner, heads: heads)
        }.sorted { $0.revision.date > $1.revision.date }
    }
}

struct FamilySnapshot: Equatable, Sendable {
    var family: Family?
    var records: [ProjectedRecord] = []
    var children: [ChildProfile] {
        records.compactMap { r in guard !r.isDeleted, case .child(let child) = r.revision.value else { return nil }; return child }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var caregivers: [Caregiver] {
        records.compactMap { r in guard !r.isDeleted, case .caregiver(let person) = r.revision.value else { return nil }; return person }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    /// Historical references retain names even after the profile leaves the active roster.
    var recordedCaregivers: [Caregiver] {
        records.compactMap { r in
            guard case .caregiver(let person) = r.revision.value, person.familyID == family?.id else {
                return nil
            }
            return person
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var pumpingHistoryCaregivers: [Caregiver] {
        let activeIDs = Set(caregivers.filter(\.isMother).map(\.id))
        let recordedIDs = Set(pumps.map(\.motherID))
        return recordedCaregivers.filter { activeIDs.contains($0.id) || recordedIDs.contains($0.id) }
    }
    var activities: [Activity] {
        let childIDs = Set(children.map(\.id))
        let caregiverIDs = canonicalCaregiverIDs
        return records.compactMap { r in
            guard !r.isDeleted,
                case .activity(let item) = careValue(r.revision.value, caregiverIDs: caregiverIDs),
                childIDs.contains(item.childID)
            else { return nil }; return item
        }
            .sorted { $0.occurredAt > $1.occurredAt }
    }
    var pumps: [PumpSession] {
        let caregiverIDs = canonicalCaregiverIDs
        return records.compactMap { r in
            guard !r.isDeleted,
                case .pumping(let item) = careValue(r.revision.value, caregiverIDs: caregiverIDs)
            else { return nil }; return item
        }
            .sorted { $0.occurredAt > $1.occurredAt }
    }
    func recentCare(for childID: UUID) -> [RecentCareEntry] {
        guard let family, children.contains(where: { $0.id == childID && $0.familyID == family.id }) else { return [] }
        let childEntries = activities.filter { $0.childID == childID && $0.familyID == family.id }.map(RecentCareEntry.activity)
        let familyPumping = pumps.filter { $0.familyID == family.id }.map(RecentCareEntry.pumping)
        return (childEntries + familyPumping).sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    func record(_ id: UUID) -> ProjectedRecord? { records.first { $0.id == id } }
    func caregiverName(_ id: UUID) -> String {
        guard let record = record(id), case .caregiver(let person) = record.revision.value,
            person.familyID == family?.id
        else { return String(localized: "Caregiver") }
        return person.name
    }
}

extension Decimal {
    var double: Double { NSDecimalNumber(decimal: self).doubleValue }
    static func input(_ text: String, locale: Locale = .current) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try? Decimal(trimmed, format: .number.locale(locale), lenient: false)
    }
}

extension FamilySnapshot {
    /// Resolve only complete, uncontested aliases. Missing/out-of-order records,
    /// identity races, and cycles keep the original history visible until reviewed.
    func canonicalCaregiverID(_ id: UUID) -> UUID {
        canonicalCaregiverIDs[id] ?? id
    }

    var canonicalCaregiverIDs: [UUID: UUID] {
        guard let family else { return [:] }
        let profiles = Dictionary(
            uniqueKeysWithValues: records.compactMap { record -> (UUID, ProjectedRecord)? in
                guard case .caregiver(let person) = record.revision.value,
                    person.familyID == family.id
                else { return nil }
                return (person.id, record)
            })
        var resolved: [UUID: UUID] = [:]
        for id in profiles.keys {
            var current = id
            var visited: Set<UUID> = []
            while visited.insert(current).inserted {
                guard let record = profiles[current],
                    case .caregiver(let person) = record.revision.value
                else { break }
                guard let next = person.mergedIntoID else {
                    resolved[id] = current
                    break
                }
                guard record.isDeleted, !record.hasConflict, person.cloudIdentity == nil,
                    current != family.ownerID
                else { break }
                current = next
            }
        }
        return resolved
    }

    func careValue(_ value: RecordValue, caregiverIDs: [UUID: UUID]? = nil) -> RecordValue {
        let ids = caregiverIDs ?? canonicalCaregiverIDs
        switch value {
        case .pumping(var pump):
            pump.motherID = ids[pump.motherID] ?? pump.motherID
            return .pumping(pump)
        case .activity(var activity):
            if case .nursing(var nursing) = activity.payload {
                nursing.caregiverID = ids[nursing.caregiverID] ?? nursing.caregiverID
                activity.payload = .nursing(nursing)
            }
            return .activity(activity)
        default: return value
        }
    }
}
