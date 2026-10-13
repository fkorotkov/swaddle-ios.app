import Foundation

struct CareContentID: Hashable, Codable, Sendable {
    let familyID: UUID
    let recordID: UUID
    var rawValue: String { "\(familyID.uuidString)/\(recordID.uuidString)" }
    init(familyID: UUID, recordID: UUID) { self.familyID = familyID; self.recordID = recordID }
    init?(_ rawValue: String) {
        let parts = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let family = UUID(uuidString: String(parts[0])), let record = UUID(uuidString: String(parts[1])) else { return nil }
        familyID = family; recordID = record
    }
}

struct CareSearchDocument: Identifiable, Equatable, Sendable {
    let key: CareContentID
    let revisionID: UUID
    let childID: UUID?
    let caregiverID: UUID?
    let subjectName: String
    let kind: ActivityKind?
    let timeZoneIdentifier: String
    let title: String
    let content: String
    let occurredAt: Date
    let createdAt: Date
    let modifiedAt: Date
    let isCareNote: Bool
    var id: String { key.rawValue }
    var displayTitle: String { "\(subjectName) · \(kind?.title ?? String(localized: "Pumping"))" }
    var previewText: String { String(content.split(separator: "\n").first ?? "") }
    var dateLabel: String {
        var format = Date.FormatStyle(date: .abbreviated, time: .shortened)
        format.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return occurredAt.formatted(format)
    }
}

enum CareSearchCatalog {
    /// Only current care entries are exposed. Deleted children, old revisions,
    /// conflicts, and unfinished timers stay hidden; retained pumping keeps its caregiver name.
    static func documents(in snapshot: FamilySnapshot, recordIDs: Set<UUID>? = nil)
        -> [CareSearchDocument]
    {
        guard let family = snapshot.family else { return [] }
        let children = Dictionary(uniqueKeysWithValues: snapshot.children.map { ($0.id, $0) })
        let caregivers = Dictionary(
            uniqueKeysWithValues: snapshot.pumpingHistoryCaregivers.map { ($0.id, $0) })
        let conflicts = Set(snapshot.records.filter(\.hasConflict).map(\.id))
        let caregiverIDs = snapshot.canonicalCaregiverIDs
        return snapshot.records.compactMap { record in
            // Onscreen context only needs the displayed entries. Keep the full
            // roster and conflict checks above; filtering the snapshot itself
            // would lose the identities and permissions of related records.
            guard recordIDs?.contains(record.id) != false else { return nil }
            guard !record.isDeleted, !record.hasConflict, record.revision.value.familyID == family.id else { return nil }
            let key = CareContentID(familyID: family.id, recordID: record.id)
            switch snapshot.careValue(record.revision.value, caregiverIDs: caregiverIDs) {
            case .activity(let activity):
                guard let child = children[activity.childID], child.familyID == family.id, activity.payload.isComplete,
                      !conflicts.contains(child.id) else { return nil }
                let note = readableNote(activity.note)
                let detail = detail(activity.payload)
                let date = timestamp(activity.occurredAt, zone: family.timeZoneIdentifier)
                let title = String(localized: "\(child.name) · \(activity.payload.kind.title) · \(date)")
                let content = [detail, note, String(localized: "Recorded for \(child.name)."), String(localized: "Occurred: \(date).")].filter { !$0.isEmpty }.joined(separator: "\n")
                return CareSearchDocument(key: key, revisionID: record.revision.id, childID: child.id, caregiverID: nil,
                    subjectName: child.name, kind: activity.payload.kind, timeZoneIdentifier: family.timeZoneIdentifier,
                    title: title, content: content, occurredAt: activity.occurredAt, createdAt: activity.createdAt,
                    modifiedAt: record.revision.date, isCareNote: activity.payload.kind == .careNote)
            case .pumping(let pump):
                guard let person = caregivers[pump.motherID], person.familyID == family.id,
                      !conflicts.contains(person.id) else { return nil }
                let date = timestamp(pump.occurredAt, zone: family.timeZoneIdentifier)
                var details = [String(localized: "\(VolumeUnit.ml.quantity(pump.totalML)) pumped for \(person.name)."), String(localized: "Pumped milk is separate from bottle intake.")]
                if let left = pump.leftML, let right = pump.rightML { details.append(String(localized: "Left: \(VolumeUnit.ml.quantity(left)). Right: \(VolumeUnit.ml.quantity(right)).")) }
                if let minutes = pump.minutes { details.append(String(localized: "Duration: \(minutes.formatted()) minutes.")) }
                details += [readableNote(pump.note), String(localized: "Occurred: \(date).")]
                return CareSearchDocument(key: key, revisionID: record.revision.id, childID: nil, caregiverID: person.id,
                    subjectName: person.name, kind: nil, timeZoneIdentifier: family.timeZoneIdentifier,
                    title: String(localized: "\(person.name) · Pumping · \(date)"), content: details.filter { !$0.isEmpty }.joined(separator: "\n"),
                    occurredAt: pump.occurredAt, createdAt: pump.createdAt, modifiedAt: record.revision.date, isCareNote: false)
            default: return nil
            }
        }.sorted { $0.occurredAt == $1.occurredAt ? $0.id < $1.id : $0.occurredAt > $1.occurredAt }
    }

    static func resolve(_ rawID: String, in snapshot: FamilySnapshot) throws -> CareSearchDocument {
        guard let key = CareContentID(rawID), key.familyID == snapshot.family?.id,
              let document = documents(in: snapshot).first(where: { $0.key == key }) else {
            throw LogError.message(String(localized: "This record is no longer available in your family. It may have been deleted, or need an edit reviewed in Swaddle."))
        }
        return document
    }

    static func matching(_ query: String, documents: [CareSearchDocument], limit: Int = 100) -> [CareSearchDocument] {
        let terms = searchWords(query)
        return Array(documents.filter { document in
            let words = searchWords(document.title + "\n" + document.content)
            // Prefixes support partial names without matching "red" inside "occurred".
            return terms.allSatisfy { term in words.contains { $0.hasPrefix(term) } }
        }.prefix(max(0, limit)))
    }

    private static func searchWords(_ text: String) -> [Substring] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { !$0.isLetter && !$0.isNumber }
    }

    static func readableNote(_ text: String) -> String {
        // Export bookkeeping is retained in the saved record, not repeated as searchable prose.
        text.components(separatedBy: "\n\nOriginal JSON:")[0].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func timestamp(_ date: Date, zone: String) -> String {
        var format = Date.FormatStyle(date: .abbreviated, time: .shortened)
        format.timeZone = TimeZone(identifier: zone) ?? .current
        return "\(date.formatted(format)) (\(format.timeZone.identifier))"
    }
    private static func detail(_ payload: ActivityPayload) -> String {
        switch payload {
        case .bottle(let bottle):
            var text = String(localized: "Bottle: \(VolumeUnit.ml.quantity(bottle.totalML)) total. Breast milk: \(VolumeUnit.ml.quantity(bottle.milkML)). Formula: \(VolumeUnit.ml.quantity(bottle.formulaML)).")
            if bottle.unknownML > 0 { text += String(localized: " Split not recorded: \(VolumeUnit.ml.quantity(bottle.unknownML)).") }
            return text
        case .diaper(let diaper): return String(localized: "Diaper: \(diaper.title).")
        case .nursing(let nursing): return String(localized: "Breastfeeding: \(Int(nursing.duration(at: .now))) seconds. Breastfeeding time is separate from bottle volume.")
        case .weight(let grams, _): return String(localized: "Weight: \(grams.formatted()) g.")
        case .length(let cm, let unit, let position):
            return String(localized: "\(position.measurementTitle): \(unit.quantity(cm)), measured \(position.title.lowercased()).")
        case .headCircumference(let cm, let unit): return String(localized: "Head circumference: \(unit.quantity(cm)).")
        case .temperature(let celsius, _, _): return String(localized: "Temperature: \(celsius.formatted()) °C.")
        case .careNote: return ""
        }
    }
}

struct SiriNavigationRequest: Identifiable, Equatable, Sendable {
    enum Destination: Equatable, Sendable { case search(String), record(String), report(familyID: UUID, childID: UUID, period: ReportPeriod) }
    let id = UUID()
    let destination: Destination
}

struct FeedingReportID: Equatable, Sendable {
    let child: CareContentID
    let period: ReportPeriod
    var rawValue: String { "\(child.rawValue)/\(period.rawValue)" }
    init(familyID: UUID, childID: UUID, period: ReportPeriod) { child = CareContentID(familyID: familyID, recordID: childID); self.period = period }
    init?(_ rawValue: String) {
        let parts = rawValue.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3, let child = CareContentID(parts.prefix(2).joined(separator: "/")), let period = ReportPeriod(rawValue: String(parts[2])) else { return nil }
        self.child = child; self.period = period
    }
    func report(in snapshot: FamilySnapshot, now: Date) throws -> FeedingReport {
        guard child.familyID == snapshot.family?.id else { throw LogError.message(String(localized: "This feeding report belongs to a different family.")) }
        let profile = try LogRules.child(child.recordID, in: snapshot)
        return FeedingReport(child: profile, period: period, snapshot: snapshot, now: now)
    }
}
