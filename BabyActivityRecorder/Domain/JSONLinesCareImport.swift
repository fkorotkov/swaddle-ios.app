import Foundation

/// A strict, versioned export path. Structured input never falls back to prose interpretation.
nonisolated enum JSONLinesCareImport {
    static let example = #"{"type":"feed","version":1,"occurredAt":"2026-05-10T08:30:00-04:00","breastMilkML":60,"formulaML":15,"totalML":75,"notes":"Finished bottle."}"#
    static let unknownExample = #"{"type":"feed","version":1,"occurredAt":"2026-05-10T11:30:00-04:00","breastMilkML":null,"formulaML":null,"totalML":90,"notes":"Split not recorded."}"#
    static let exportInstructions = String(localized: """
    Export bottle feeds for one child as Swaddle JSON Lines version 1. Output one complete JSON object per line, without headings, Markdown code fences, or an enclosing array. Do not invent missing dates or quantities. Preserve source mL; if conversion is needed, use the source convention: exact US fl oz = 29.5735295625 mL, or Swaddle oz = 30 mL.
    Required fields: "type":"feed", "version":1, "occurredAt" as an ISO 8601 timestamp including seconds and UTC offset (or Z), and "breastMilkML", "formulaML", "totalML" in milliliters as JSON numbers. Total must be positive; components cannot be negative. For a known split their sum must match totalML within 0.01 mL; the component sum is saved. For an unknown split use null for BOTH components and keep the known totalML. Use 0 for an absent component of a known split.
    Optional fields: "notes" (verbatim string, escape newlines as \\n), "timezone" (IANA time zone matching the offset at that timestamp), "id" (stable original entry ID as a nonempty string), "source" (nonempty exporting-app name, requires id; defaults to "jsonl"). Preserve the same source and ID across exports. IDs are scoped to the selected child and family. Matching IDs are excluded, never used to overwrite saved entries; without IDs, similar times and amounts are flagged. No other fields are accepted.
    Up to 50,000 characters or 500 lines per batch. Select the child in Swaddle, paste into Care notes, review, then save. An invalid line stops the entire batch.
    Example known split:
    \(example)
    Example unknown split:
    \(unknownExample)
    """)

    static func recognizes(_ text: String) -> Bool {
        let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first
        // Arrays receive an actionable format error rather than becoming a care note.
        return first == "{" || first == "["
    }

    static func parse(_ lines: [String]) throws -> [CareImportDraft] {
        var rows: [CareImportDraft] = []
        for (index, original) in lines.enumerated() {
            let source = original.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { continue }
            let line = index + 1
            func fail(_ message: String) -> LogError { .message(String(localized: "Line \(line): \(message)")) }
            guard source.first == "{" else { throw fail(String(localized: "Use one JSON object per line, without an array, headings, or code fences.")) }
            let entry: Entry
            do { entry = try JSONDecoder().decode(Entry.self, from: Data(source.utf8)) }
            catch let error as FormatError { throw fail(error.message) }
            catch DecodingError.keyNotFound(let key, _) { throw fail(String(localized: "Missing required field “\(key.stringValue)”.")) }
            catch DecodingError.typeMismatch(_, let context) { throw fail(String(localized: "Check the value of “\(context.codingPath.last?.stringValue ?? "entry")”. Amounts must be JSON numbers or null.")) }
            catch DecodingError.valueNotFound(_, let context) { throw fail(String(localized: "“\(context.codingPath.last?.stringValue ?? "entry")” cannot be null.")) }
            catch { throw fail(String(localized: "Invalid JSON. Keep each complete object on one line; use \\n for a newline inside notes.")) }
            guard entry.version == 1 else { throw fail(String(localized: "Unsupported version. Use version 1.")) }
            guard entry.type == "feed" else { throw fail(String(localized: "Version 1 supports bottle feeds only. Use type “feed”.")) }
            guard let offsetZone = offsetZone(entry.occurredAt) else {
                throw fail(String(localized: "occurredAt needs a full date, time, seconds, and UTC offset, such as 2026-05-10T08:30:00-04:00."))
            }
            let timestamp = try StructuredCareImport.date(entry.occurredAt, timeZone: offsetZone, line: line)
            var zone = offsetZone
            if let identifier = entry.timezone {
                guard let declared = TimeZone(identifier: identifier), declared.secondsFromGMT(for: timestamp) == offsetZone.secondsFromGMT(for: timestamp) else {
                    throw fail(String(localized: "timezone must be a valid time zone matching the UTC offset at occurredAt."))
                }
                zone = declared
            }
            guard entry.totalML > 0, !entry.totalML.isNaN else { throw fail(String(localized: "totalML must be a number greater than zero.")) }
            var row = CareImportDraft(kind: .bottle, source: source, sourceLine: line, block: index,
                timestamp: timestamp, timeWasExplicit: true, unit: .ml, reportedTotalML: entry.totalML,
                timeZoneIdentifier: zone.identifier, isStructured: true, note: entry.notes ?? "")
            if let id = entry.id {
                guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw fail(String(localized: "id must be a nonempty string, or omit it.")) }
                let origin = entry.source ?? "jsonl"
                guard !origin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw fail(String(localized: "source must be a nonempty string, or omit it.")) }
                row.importIdentity = ImportIdentity(source: origin, id: id)
            } else if entry.source != nil { throw fail(String(localized: "Include an id when providing a source.")) }
            switch (entry.breastMilkML, entry.formulaML) {
            case (.some(let milk), .some(let formula)):
                guard milk >= 0, formula >= 0, !milk.isNaN, !formula.isNaN, milk + formula > 0 else {
                    throw fail(String(localized: "breastMilkML and formulaML must be nonnegative numbers with a positive combined volume."))
                }
                guard abs(milk + formula - entry.totalML) <= Decimal(string: "0.01")! else {
                    throw fail(String(localized: "breastMilkML + formulaML must equal totalML (within 0.01 mL for rounding)."))
                }
                row.milk = number(milk); row.formula = number(formula)
            case (nil, nil):
                row.unknown = number(entry.totalML)
                row.reviewReasons.append("Split not recorded. This volume counts toward total intake, separately from milk and formula.")
            default: throw fail(String(localized: "Use numbers for both components, or null for both when the split is unknown."))
            }
            // Keep the exact original JSON as well as readable, unescaped caregiver wording.
            row.source = [entry.notes, "Original JSON: \(source)"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
            rows.append(row)
        }
        guard !rows.isEmpty else { throw LogError.message(String(localized: "No JSON entries found.")) }
        return rows
    }

    static func number(_ value: Decimal) -> String { number(value, locale: .current) }
    static func number(_ value: Decimal, locale: Locale) -> String {
        value.formatted(.number.locale(locale).grouping(.never).precision(.fractionLength(0...20)))
    }
    static func offsetZone(_ text: String) -> TimeZone? {
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { return nil }
        if text.hasSuffix("Z") { return TimeZone(secondsFromGMT: 0) }
        let tail = String(text.suffix(6))
        let pieces = tail.dropFirst().split(separator: ":")
        guard let hours = Int(pieces[0]), let minutes = Int(pieces[1]), hours <= 23, minutes < 60 else { return nil }
        return TimeZone(secondsFromGMT: (hours * 3600 + minutes * 60) * (tail.first == "-" ? -1 : 1))
    }

    private struct FormatError: Error { let message: String }
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    private struct Entry: Decodable {
        let type: String
        let version: Int
        let occurredAt: String
        let breastMilkML: Decimal?
        let formulaML: Decimal?
        let totalML: Decimal
        let notes: String?
        let timezone: String?
        let source: String?
        let id: String?
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: Key.self)
            let allowed = Set(["type", "version", "occurredAt", "breastMilkML", "formulaML", "totalML", "notes", "timezone", "source", "id"])
            if let unknown = values.allKeys.map(\.stringValue).sorted().first(where: { !allowed.contains($0) }) {
                throw FormatError(message: String(localized: "Unknown field “\(unknown)”. Check Format tips for the supported fields."))
            }
            func key(_ name: String) -> Key { Key(stringValue: name)! }
            func number(_ name: String, nullable: Bool = false) throws -> Decimal? {
                let field = key(name)
                guard values.contains(field) else { throw DecodingError.keyNotFound(field, .init(codingPath: [], debugDescription: "Required")) }
                if nullable, try values.decodeNil(forKey: field) { return nil }
                // Decimal decoding alone can accept quoted numbers; require a JSON numeric token.
                let finite = try values.decode(Double.self, forKey: field)
                guard finite.isFinite else { throw FormatError(message: String(localized: "\(name) must be a finite JSON number.")) }
                return try values.decode(Decimal.self, forKey: field)
            }
            type = try values.decode(String.self, forKey: key("type"))
            version = try values.decode(Int.self, forKey: key("version"))
            occurredAt = try values.decode(String.self, forKey: key("occurredAt"))
            breastMilkML = try number("breastMilkML", nullable: true)
            formulaML = try number("formulaML", nullable: true)
            totalML = try number("totalML")!
            notes = try values.decodeIfPresent(String.self, forKey: key("notes"))
            timezone = try values.decodeIfPresent(String.self, forKey: key("timezone"))
            source = try values.decodeIfPresent(String.self, forKey: key("source"))
            id = try values.decodeIfPresent(String.self, forKey: key("id"))
        }
    }
}
