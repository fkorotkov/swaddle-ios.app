import Foundation
import Testing
@testable import LittleLogCore

struct StructuredCareImportTests {
    let zone = TimeZone(identifier: "America/New_York")!
    let day = ISO8601DateFormatter().date(from: "2026-05-10T12:00:00Z")!
    let now = ISO8601DateFormatter().date(from: "2026-06-01T12:00:00Z")!
    let child = ChildProfile(familyID: UUID(), name: "Test child")

    func parse(_ text: String) throws -> [CareImportDraft] {
        try CareNoteParser.parse(text, firstDay: day, timeZone: zone, defaultUnit: .oz)
    }
    @Test func columnsSeparateTotalsComponentsAndIncidentalNumbers() throws {
        let text = """
        Timezone: America/New_York. BM = breast milk. All feeds are bottles. Volumes in ml rounded to 2 decimals.
        2026-05-10 23:13 | Mixed BM/formula | 64.15 ml | Breast milk 2 oz; formula 5 ml.
        2026-05-11 03:00 | BM | 118.29 ml | Breast milk 4 oz. Spit-up at 04:20; caregiver wondered if 4 oz was too much. Dry diaper.
        2026-05-11 06:00 | Formula | 59.15 ml | Formula 2 oz. Report time used; exact time unspecified.
        2026-05-11 08:00 | Mixed BM/formula | 95 ml | Split not recorded.
        """
        let rows = try parse(text)
        #expect(rows.count == 4 && rows.allSatisfy { $0.kind == .bottle && $0.isStructured })
        let entries = try rows.map { try $0.activity(child: child, authorID: UUID(), now: now) }
        guard case .bottle(let mixed) = entries[0].payload, case .bottle(let pure) = entries[1].payload else { Issue.record("Expected bottles"); return }
        #expect(mixed.milkML == Decimal(string: "59.147059125") && mixed.formulaML == 5)
        #expect(pure.milkML == Decimal(string: "118.29"))
        #expect(entries[1].occurredAt == ISO8601DateFormatter().date(from: "2026-05-11T07:00:00Z"))
        #expect(entries[1].note.contains("Dry diaper"))
        #expect(rows[2].reviewReasons.contains { $0.contains("Report time") })
        let summary = ActivitySummary(activities: entries, childID: child.id, end: now)
        #expect(summary.bottles == 4 && summary.changes == 0)
        #expect(summary.unknownML == 95)
        #expect(summary.totalML == summary.milkML + summary.formulaML + 95)
    }
    @Test func fullExportSkipsMetadataAndKeepsISOSecondsAndOffsets() throws {
        let text = """
        Little Days — complete feeding log
        Timezone: America/New_York. Ounces are US fluid ounces.
        Entries: 2. All saved feeding entries included, through the export time.
        Amounts below are rounded to 3 decimals; JSON preserves stored numeric precision.
        Two components marked unknown means the mixed feed total is known but its breast milk/formula split was not recorded.
        2026-05-10T13:59:53-04:00 | Bottle feed | mixed | Total: 73.934 ml (2.5 oz) | Breast milk: 59.147 ml (2 oz) | Formula: 14.787 ml (0.5 oz) | Notes: A note with another 2 oz mentioned.
        2026-05-10T16:31:07-04:00 | Bottle feed | mixed | Total: 90 ml (3.043 oz) | Breast milk: unknown | Formula: unknown
        """
        let rows = try parse(text)
        #expect(rows.count == 2)
        #expect(rows[0].timestamp == ISO8601DateFormatter().date(from: "2026-05-10T17:59:53Z"))
        #expect(rows[0].milk == "59.147" && rows[0].formula == "14.787")
        #expect(rows[1].unknown == "90" && rows[1].milk.isEmpty && rows[1].formula.isEmpty)
        #expect(rows.allSatisfy { $0.timeZoneIdentifier == "America/New_York" })
        #expect(try rows.allSatisfy { try $0.activity(child: child, authorID: UUID(), now: now).payload.kind == .bottle })
    }
    @Test func componentFractionsAndMixedUnitsAreConvertedIndependently() throws {
        for (fraction, ounces) in [("½", "0.5"), ("1/2", "0.5"), ("1½", "1.5"), ("2 1/2", "2.5"), ("21/2", "2.5")] {
            let amount = Decimal(string: ounces)!
            let sourceML = amount * Decimal(string: "29.5735295625")!
            let total = (60 + sourceML).formatted(.number.grouping(.never).precision(.fractionLength(2)))
            let rows = try parse("2026-05-10 08:00 | Mixed BM/formula | \(total) ml | Breast milk 60 ml; formula \(fraction) oz.")
            let entry = try rows[0].activity(child: child, authorID: UUID(), now: now)
            guard case .bottle(let bottle) = entry.payload else { Issue.record("Expected bottle"); continue }
            #expect(bottle.milkML == 60 && bottle.formulaML == sourceML)
            if fraction == "21/2" { #expect(rows[0].reviewReasons.contains { $0.contains("Confirm this fraction") }) }
        }
        let repeated = try parse("2026-05-10 08:00 | Mixed BM/formula | 147.87 ml | Breast milk 21/2 oz; formula 21/2 oz.")[0]
        #expect(repeated.reviewReasons.count == 1)
    }
    @Test func conflictingOrPartialComponentsRequireAnExplicitCorrection() throws {
        for line in [
            "2026-05-10 08:00 | Mixed BM/formula | 100 ml | Breast milk 90 ml; formula 30 ml.",
            "2026-05-10 08:00 | Mixed BM/formula | 100 ml | Breast milk 60 ml; formula unknown.",
            "2026-05-10 08:00 | BM | an unknown amount"
        ] {
            let row = try parse(line)[0]
            #expect(row.amountIssue != nil)
            #expect(throws: LogError.self) { try row.activity(child: child, authorID: UUID(), now: now) }
        }
    }
    @Test func badDatesTimeZonesAndNegativeVolumesCannotBeSaved() throws {
        for line in ["2026-02-30 10:00", "2026-05-10 25:00", "2026-03-08 02:30", "2026-02-30T10:00:00-04:00", "2026-05-10T25:00:00Z", "2026-05-10T10:00:00-04:99"] {
            #expect(throws: LogError.self) { try parse("\(line) | BM | 60 ml") }
        }
        #expect(throws: LogError.self) { try parse("Timezone: Mars/Olympus\n2026-05-10 10:00 | BM | 60 ml") }
        #expect(throws: LogError.self) { try parse("Timezone: America/New_York\nTimezone: Europe/London") }
        let row = try parse("2026-05-10 10:00 | BM | -60 ml")[0]
        #expect(throws: LogError.self) { try row.activity(child: child, authorID: UUID(), now: now) }
    }
    @Test func fractionalISOSecondsRemainPrecise() throws {
        let row = try parse("2026-05-10T08:15:27.125-04:00 | BM | 60 ml")[0]
        let formatter = ISO8601DateFormatter(); formatter.formatOptions.insert(.withFractionalSeconds)
        #expect(row.timestamp == formatter.date(from: "2026-05-10T12:15:27.125Z"))
    }
    @Test func declaredZoneOverridesFamilyZoneAndExplicitDatesDoNotRollOver() throws {
        let rows = try CareNoteParser.parse("Timezone: Europe/London\n2026-05-10 23:00 | BM | 60 ml\n2026-05-10 01:00 | BM | 70 ml", firstDay: day, timeZone: zone, defaultUnit: .ml)
        #expect(rows[0].timestamp == ISO8601DateFormatter().date(from: "2026-05-10T22:00:00Z"))
        #expect(rows[1].timestamp == ISO8601DateFormatter().date(from: "2026-05-10T00:00:00Z"))
        let overnight = try parse("2026-05-10 23:30 | BM | 60 ml\nFeed bm 1 am 2oz")
        #expect(overnight[1].timestamp == ISO8601DateFormatter().date(from: "2026-05-11T05:00:00Z"))
    }
    @Test func longerExportIsAcceptedButLimitsRemainBounded() throws {
        let lines = (0..<66).map { index in
            "2026-05-10 \(String(format: "%02d:%02d", index / 60, index % 60)) | BM | 90 ml | " + String(repeating: "An original observation. ", count: 6)
        }
        let text = lines.joined(separator: "\n")
        #expect(text.count > 8000)
        #expect(try parse(text).count == 66)
        #expect(throws: LogError.self) { try parse(String(repeating: "x", count: CareNoteParser.maximumCharacters + 1)) }
        #expect(throws: LogError.self) { try parse(Array(repeating: "note", count: CareNoteParser.maximumLines + 1).joined(separator: "\n")) }
        #expect(throws: LogError.self) { try parse("Timezone: America/New_York. BM = breast milk. All feeds are bottles.") }
    }
    @Test func legacyBottlesDecodeAndUnknownTotalsSurviveRoundTripAndValidation() throws {
        let legacy = Data(#"{"milkML":60,"formulaML":15,"unit":"ml"}"#.utf8)
        let bottle = try JSONDecoder().decode(Bottle.self, from: legacy)
        #expect(bottle.unknownML == 0 && bottle.totalML == 75)
        let unknown = Bottle(milkML: 0, formulaML: 0, unit: .ml, unclassifiedML: 95)
        #expect(try JSONDecoder().decode(Bottle.self, from: JSONEncoder().encode(unknown)) == unknown)
        try unknown.validate()
        #expect(throws: LogError.self) { try Bottle(milkML: 60, formulaML: 0, unit: .ml, unclassifiedML: 95).validate() }
        let activity = Activity(familyID: child.familyID, childID: child.id, occurredAt: day, authorID: UUID(), payload: .bottle(unknown))
        let envelope = RecordEnvelope(value: .activity(activity))
        #expect(envelope.version == 2)
        #expect(try JSONDecoder().decode(RecordEnvelope.self, from: JSONEncoder().encode(envelope)) == envelope)
    }
    @Test func reviewUnitChangesAndUnknownToggleKeepTheStatedTotal() throws {
        var row = try parse("2026-05-10 08:00 | Mixed BM/formula | 90 ml | Breast milk 60 ml; formula unknown.")[0]
        row.setSplitUnknown(true)
        #expect(row.unknown == "90" && row.milk.isEmpty && row.formula.isEmpty && row.amountIssue == nil)
        row.changeUnit(.oz)
        let entry = try row.activity(child: child, authorID: UUID(), now: now)
        guard case .bottle(let bottle) = entry.payload else { Issue.record("Expected bottle"); return }
        #expect(abs(bottle.unknownML - 90) < Decimal(string: "0.000000001")!)
        row.setSplitUnknown(false)
        #expect(row.unknown.isEmpty && row.milk.isEmpty && row.formula.isEmpty)
        #expect(throws: LogError.self) { try row.activity(child: child, authorID: UUID(), now: now) }
    }
    @Test func duplicateComparisonHandlesUnitAndExportRounding() throws {
        let row = try parse("2026-05-10 08:00 | BM | 59.15 ml")[0]
        let entry = Activity(familyID: child.familyID, childID: child.id, occurredAt: row.timestamp!, authorID: UUID(), payload: .bottle(Bottle(milkML: Decimal(string: "59.147059125")!, formulaML: 0, unit: .oz)))
        #expect(row.resembles(entry, child: child, authorID: UUID()))
        var other = entry; other.payload = .bottle(Bottle(milkML: 0, formulaML: 0, unit: .ml, unclassifiedML: Decimal(string: "59.15")))
        #expect(!row.resembles(other, child: child, authorID: UUID()))
    }
}
