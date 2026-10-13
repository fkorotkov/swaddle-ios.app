import Foundation

nonisolated enum JSONLinesPumpImport {
    static let example = #"{"type":"pump","version":1,"occurredAt":"2026-05-10T08:30:00-04:00","totalML":105,"leftML":60,"rightML":45,"durationMinutes":15,"notes":"Morning session.","source":"example-app","id":"pump-123"}"#
    static let totalOnlyExample = #"{"type":"pump","version":1,"occurredAt":"2026-05-10T12:30:00-04:00","totalML":103.50735346875,"leftML":null,"rightML":null,"durationMinutes":null}"#

    static let exportInstructions = String(localized: """
    Export pumping sessions for one caregiver as Swaddle JSON Lines version 1. Output one complete JSON object per line, without headings, Markdown fences, or an array. Do not mix pumping and feeding in one batch. Do not invent missing values.
    Required: "type":"pump", "version":1, "occurredAt" as an ISO 8601 timestamp including seconds and a UTC offset (or Z), and "totalML" as a positive JSON number in mL. totalML may be null ONLY when both leftML and rightML are known numbers with a positive sum; their sum becomes the total. Preserve source mL and decimal precision. If conversion is needed, use the source convention: exact US fl oz = 29.5735295625 mL, or Swaddle oz = 30 mL.
    Optional: "leftML" and "rightML" (nonnegative numbers, BOTH supplied and summing to totalML within 0.01 mL, or BOTH null/omitted when unknown); "durationMinutes" (positive number or null/omitted); "notes" (verbatim string, escape newlines as \\n); "timezone" (IANA time zone matching occurredAt's offset); "id" (stable original ID); "source" (exporting-app name, requires id; defaults to "jsonl"). No other fields are accepted.
    Keep source and ID unchanged across exports. IDs are scoped to the selected caregiver and family. Existing IDs are excluded, never overwritten. Choose the pumping profile in Swaddle before reviewing and saving. Pumped milk is separate from child intake. Maximum 50,000 characters or 500 lines.
    \(example)
    \(totalOnlyExample)
    """)

    static func recognizes(_ text: String) -> Bool {
        struct Header: Decodable { let type: String }
        let normalized = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}")))
        guard normalized.first == "{", let first = normalized.components(separatedBy: .newlines).first else { return false }
        return (try? JSONDecoder().decode(Header.self, from: Data(first.utf8)))?.type == "pump"
    }

    static func parse(_ text: String) throws -> [PumpImportDraft] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
        let lines = normalized.components(separatedBy: .newlines)
        guard text.count <= CareNoteParser.maximumCharacters, lines.count <= CareNoteParser.maximumLines else {
            throw LogError.message(String(localized: "Import up to 50,000 characters or 500 lines at a time."))
        }
        var rows: [PumpImportDraft] = []
        for (index, original) in lines.enumerated() {
            let source = original.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { continue }
            let line = index + 1
            func fail(_ message: String) -> LogError { .message(String(localized: "Line \(line): \(message)")) }
            let entry: Entry
            do { entry = try JSONDecoder().decode(Entry.self, from: Data(source.utf8)) }
            catch let error as FormatError { throw fail(error.message) }
            catch DecodingError.keyNotFound(let key, _) { throw fail(String(localized: "Missing required field “\(key.stringValue)”.")) }
            catch DecodingError.typeMismatch(_, let context) { throw fail(String(localized: "Check “\(context.codingPath.last?.stringValue ?? "entry")”. Use JSON numbers for amounts and duration.")) }
            catch DecodingError.valueNotFound(_, let context) { throw fail(String(localized: "“\(context.codingPath.last?.stringValue ?? "entry")” cannot be null.")) }
            catch { throw fail(String(localized: "Invalid JSON. Use one complete object per line, without headings, code fences, or an array.")) }
            guard entry.version == 1 else { throw fail(String(localized: "Unsupported version. Use version 1.")) }
            guard entry.type == "pump" else { throw fail(String(localized: "Import pumping separately from feeds. Use type “pump” for every line in this batch.")) }
            guard let offset = JSONLinesCareImport.offsetZone(entry.occurredAt) else {
                throw fail(String(localized: "occurredAt needs a full date, time, seconds, and UTC offset, such as 2026-05-10T08:30:00-04:00."))
            }
            let date = try StructuredCareImport.date(entry.occurredAt, timeZone: offset, line: line)
            var zone = offset
            if let identifier = entry.timezone {
                guard let declared = TimeZone(identifier: identifier), declared.secondsFromGMT(for: date) == offset.secondsFromGMT(for: date) else {
                    throw fail(String(localized: "timezone must match the UTC offset at occurredAt."))
                }
                zone = declared
            }
            if let total = entry.totalML, total <= 0 { throw fail(String(localized: "totalML must be greater than zero.")) }
            let total: Decimal
            switch (entry.leftML, entry.rightML) {
            case (.some(let left), .some(let right)):
                guard left >= 0, right >= 0, left + right > 0,
                      entry.totalML.map({ abs(left + right - $0) <= Decimal(string: "0.01")! }) ?? true else {
                    throw fail(String(localized: "Left and right must be nonnegative and add up to totalML within 0.01 mL."))
                }
                total = entry.totalML ?? left + right
            case (nil, nil):
                guard let stated = entry.totalML else { throw fail(String(localized: "Supply a positive totalML, or both recorded leftML and rightML amounts. No volume can be inferred when all are unknown.")) }
                total = stated
            default: throw fail(String(localized: "Supply both leftML and rightML, or leave both null/omitted when the split is unknown."))
            }
            if let minutes = entry.durationMinutes, minutes <= 0 { throw fail(String(localized: "durationMinutes must be positive, null, or omitted.")) }
            var identity: ImportIdentity?
            if let id = entry.id {
                let origin = entry.source ?? "jsonl"
                guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw fail(String(localized: "id and source must be nonempty strings.")) }
                identity = ImportIdentity(source: origin, id: id)
            } else if entry.source != nil { throw fail(String(localized: "Include an id when providing a source.")) }
            rows.append(PumpImportDraft(sourceLine: line, sourceJSON: source, occurredAt: date, timeZoneIdentifier: zone.identifier,
                total: JSONLinesCareImport.number(total), left: entry.leftML.map(JSONLinesCareImport.number) ?? "",
                right: entry.rightML.map(JSONLinesCareImport.number) ?? "", duration: entry.durationMinutes.map(JSONLinesCareImport.number) ?? "",
                notes: entry.notes ?? "", importIdentity: identity,
                reviewReason: entry.totalML == nil ? String(localized: "Total calculated from the recorded left and right amounts.") : nil))
        }
        guard !rows.isEmpty else { throw LogError.message(String(localized: "No pumping sessions found.")) }
        return rows
    }

    private struct FormatError: Error { let message: String }
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    private struct Entry: Decodable {
        let type: String, occurredAt: String
        let version: Int
        let totalML: Decimal?
        let leftML: Decimal?, rightML: Decimal?, durationMinutes: Decimal?
        let notes: String?, timezone: String?, source: String?, id: String?

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: Key.self)
            let allowed = Set(["type", "version", "occurredAt", "totalML", "leftML", "rightML", "durationMinutes", "notes", "timezone", "source", "id"])
            if let unknown = values.allKeys.map(\.stringValue).sorted().first(where: { !allowed.contains($0) }) {
                throw FormatError(message: String(localized: "Unknown pumping field “\(unknown)”. Import feeds and pumping in separate batches."))
            }
            func key(_ name: String) -> Key { Key(stringValue: name)! }
            func number(_ name: String, optional: Bool = false) throws -> Decimal? {
                let field = key(name)
                if optional {
                    if !values.contains(field) { return nil }
                    if try values.decodeNil(forKey: field) { return nil }
                }
                let finite = try values.decode(Double.self, forKey: field)
                guard finite.isFinite else { throw FormatError(message: String(localized: "\(name) must be a finite JSON number.")) }
                return try values.decode(Decimal.self, forKey: field)
            }
            type = try values.decode(String.self, forKey: key("type"))
            version = try values.decode(Int.self, forKey: key("version"))
            occurredAt = try values.decode(String.self, forKey: key("occurredAt"))
            totalML = try values.decodeNil(forKey: key("totalML")) ? nil : number("totalML")
            leftML = try number("leftML", optional: true)
            rightML = try number("rightML", optional: true)
            durationMinutes = try number("durationMinutes", optional: true)
            notes = try values.decodeIfPresent(String.self, forKey: key("notes"))
            timezone = try values.decodeIfPresent(String.self, forKey: key("timezone"))
            source = try values.decodeIfPresent(String.self, forKey: key("source"))
            id = try values.decodeIfPresent(String.self, forKey: key("id"))
        }
    }
}

struct PumpImportDraft: Identifiable, Equatable, Sendable {
    var id = UUID()
    var sourceLine: Int
    var sourceJSON: String
    var occurredAt: Date
    var timeZoneIdentifier: String
    var total: String
    var left: String
    var right: String
    var duration: String
    var notes: String
    var importIdentity: ImportIdentity?
    var included = true
    var duplicateIdentity = false
    var reviewReason: String?

    func session(mother: Caregiver, authorID: UUID, now: Date = .now) throws -> PumpSession {
        guard !duplicateIdentity else { throw LogError.message(String(localized: "This source and ID are already imported. Edit the existing session to correct it.")) }
        guard mother.isMother else { throw LogError.message(String(localized: "Choose a pumping profile.")) }
        try LogRules.past(occurredAt, now: now)
        guard let totalML = Decimal.input(total), totalML > 0, !totalML.isNaN else { throw LogError.message(String(localized: "Enter a pumping total greater than zero.")) }
        var volume = totalML
        var leftML: Decimal?, rightML: Decimal?
        if !left.isEmpty || !right.isEmpty {
            guard let l = Decimal.input(left), let r = Decimal.input(right), !l.isNaN, !r.isNaN, l >= 0, r >= 0,
                  l + r > 0, abs(l + r - totalML) <= Decimal(string: "0.01")! else {
                throw LogError.message(String(localized: "Left and right must add up to the total within 0.01 mL. Leave both blank for a total-only session."))
            }
            leftML = l; rightML = r; volume = l + r
        }
        let minutes = duration.isEmpty ? nil : Decimal.input(duration)
        if !duration.isEmpty, minutes == nil || minutes!.isNaN || minutes! <= 0 { throw LogError.message(String(localized: "Enter a positive duration, or leave it blank.")) }
        let note = [notes, "Original JSON: \(sourceJSON)"].filter { !$0.isEmpty }.joined(separator: "\n\n")
        return PumpSession(id: id, familyID: mother.familyID, motherID: mother.id, occurredAt: occurredAt, authorID: authorID,
                           source: "Text import", totalML: volume, leftML: leftML, rightML: rightML, unit: .ml, minutes: minutes,
                           note: note, importIdentity: importIdentity, timeZoneIdentifier: timeZoneIdentifier)
    }

    static func excludingDuplicates(_ rows: [Self], existing: [PumpSession], mother: Caregiver, authorID: UUID) -> [Self] {
        var seen = existing.filter { $0.familyID == mother.familyID && $0.motherID == mother.id }
        return rows.map { draft in
            var row = draft
            if let identity = row.importIdentity, seen.contains(where: { $0.importIdentity == identity }) {
                row.included = false; row.duplicateIdentity = true
                row.reviewReason = "Already imported, or repeated earlier in this report. Excluded by source and ID."
            } else if let proposed = try? row.session(mother: mother, authorID: authorID), seen.contains(where: {
                abs($0.occurredAt.timeIntervalSince(proposed.occurredAt)) < 60 && abs($0.totalML - proposed.totalML) <= Decimal(string: "0.01")!
            }) {
                row.included = false
                row.reviewReason = "A similar session already exists or appears earlier in this report. Review before selecting it."
            }
            if let session = try? draft.session(mother: mother, authorID: authorID) { seen.append(session) }
            return row
        }
    }
}
