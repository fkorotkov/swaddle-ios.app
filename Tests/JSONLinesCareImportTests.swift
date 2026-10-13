import Foundation
import Testing
@testable import LittleLogCore

struct JSONLinesCareImportTests {
    let child = ChildProfile(familyID: UUID(), name: "Test child")
    let author = UUID()
    let now = ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")!
    func parse(_ text: String) throws -> [CareImportDraft] {
        try CareNoteParser.parse(text, firstDay: .now, timeZone: TimeZone(identifier: "Asia/Tokyo")!, defaultUnit: .oz)
    }
    func replacing(_ original: String, with next: String) -> String {
        JSONLinesCareImport.example.replacingOccurrences(of: original, with: next)
    }
    @Test func detectsWhitespaceBOMAndCRLFWhileKeepingPhysicalLineNumbers() throws {
        let rows = try parse("\u{feff} \r\n\r\n\(JSONLinesCareImport.example)\r\n\r\n\(JSONLinesCareImport.unknownExample)\r\n")
        #expect(rows.count == 2 && rows.map(\.sourceLine) == [3, 5])
        #expect(rows.allSatisfy { $0.isStructured && $0.kind == .bottle && $0.unit == .ml })
        #expect(rows[0].timestamp == ISO8601DateFormatter().date(from: "2026-05-10T12:30:00Z"))
        #expect(rows[0].milk == "60" && rows[0].formula == "15")
        #expect(rows[1].unknown == "90" && rows[1].milk.isEmpty && rows[1].formula.isEmpty)
        let entries = try rows.map { try $0.activity(child: child, authorID: author, now: now) }
        let summary = ActivitySummary(activities: entries, childID: child.id)
        #expect(summary.totalML == 165 && summary.milkML == 60 && summary.formulaML == 15 && summary.unknownML == 90)
    }
    @Test func notesStayVerbatimAndNeverCreateEvents() throws {
        let text = replacing("Finished bottle.", with: #"Pee at 09:00. Another 4 oz mentioned.\nCaregiver said \"spit-up\"."#)
        let rows = try parse(text)
        #expect(rows.count == 1)
        let entry = try rows[0].activity(child: child, authorID: author, now: now)
        #expect(entry.note.hasPrefix("Pee at 09:00. Another 4 oz mentioned.\nCaregiver said \"spit-up\"."))
        #expect(entry.note.contains("Original JSON: " + text))
        #expect(rows[0].milk == "60" && rows[0].formula == "15")
    }
    @Test func preciseNumbersAndFractionalSecondsSurvive() throws {
        let text = replacing("60", with: "59.147059125").replacingOccurrences(of: "15", with: "14.78676478125")
            .replacingOccurrences(of: "75", with: "73.93382390625").replacingOccurrences(of: "08:30:00-04:00", with: "12:30:00.125Z")
        let row = try parse(text)[0]
        #expect(Decimal.input(row.milk) == Decimal(string: "59.147059125"))
        #expect(Decimal.input(row.formula) == Decimal(string: "14.78676478125"))
        let formatter = ISO8601DateFormatter(); formatter.formatOptions.insert(.withFractionalSeconds)
        #expect(row.timestamp == formatter.date(from: "2026-05-10T12:30:00.125Z"))
    }
    @Test func invalidLineRejectsEntireBatchWithLineNumber() throws {
        for broken in ["{bad}", "Feed bm 2 oz", "[" + JSONLinesCareImport.example + "]", "{", "null"] {
            do { _ = try parse(JSONLinesCareImport.example + "\n\n" + broken); Issue.record("Expected rejection") }
            catch { #expect(error.localizedDescription.contains("Line 3:")) }
        }
        #expect(throws: LogError.self) { try parse("[" + JSONLinesCareImport.example + "]") }
    }
    @Test func schemaRejectsMissingWrongAndUnknownFields() throws {
        for text in [
            replacing(#""version":1"#, with: #""version":2"#),
            replacing(#""type":"feed""#, with: #""type":"pump""#),
            replacing(#""formulaML":15,"#, with: ""),
            replacing(#""totalML":75,"#, with: ""),
            replacing(#""notes""#, with: #""child""#),
            replacing(#""breastMilkML":60"#, with: #""breastMilkML":"60""#),
            replacing(#""breastMilkML":60"#, with: #""breastMilkML":true"#),
            replacing(#""breastMilkML":60"#, with: #""breastMilkML":null"#),
            replacing(#""totalML":75"#, with: #""totalML":null"#)
        ] { #expect(throws: LogError.self) { try parse(text) } }
    }
    @Test func amountsRejectNegativeZeroNonfiniteAndInconsistentTotals() throws {
        for text in [
            replacing(#""breastMilkML":60"#, with: #""breastMilkML":-60"#),
            replacing(#""totalML":75"#, with: #""totalML":0"#),
            replacing(#""totalML":75"#, with: #""totalML":76"#),
            replacing(#""totalML":75"#, with: #""totalML":1e999"#),
            replacing(#""totalML":75"#, with: #""totalML":NaN"#)
        ] { #expect(throws: LogError.self) { try parse(text) } }
        let row = try parse(replacing(#""totalML":75"#, with: #""totalML":75.01"#))[0]
        let entry = try row.activity(child: child, authorID: author, now: now)
        #expect(entry.payload == .bottle(Bottle(milkML: 60, formulaML: 15, unit: .ml)))
    }
    @Test func explicitOffsetsIgnoreFamilyZoneAndDeclaredZonesMustAgree() throws {
        let row = try parse(replacing(#""notes":"Finished bottle.""#, with: #""timezone":"America/New_York""#))[0]
        #expect(row.timeZoneIdentifier == "America/New_York")
        for date in ["2026-05-10T08:30:00", "2026-02-30T08:30:00Z", "2026-05-10T25:00:00Z", "2026-05-10T08:30:00-04:99"] {
            #expect(throws: LogError.self) { try parse(replacing("2026-05-10T08:30:00-04:00", with: date)) }
        }
        for zone in ["Mars/Olympus", "Asia/Tokyo"] {
            #expect(throws: LogError.self) { try parse(replacing(#""notes":"Finished bottle.""#, with: "\"timezone\":\"\(zone)\"")) }
        }
        let future = try parse(replacing("2026-05-10", with: "2999-05-10"))[0]
        #expect(throws: LogError.self) { try future.activity(child: child, authorID: author, now: now) }
    }
    @Test func sourceIDsSurviveCodingAndPreventChangedReimportsForSameChild() throws {
        let input = replacing(#""notes":"Finished bottle.""#, with: #""id":"original-1","source":"example""#)
        let row = try parse(input)[0]
        let saved = try row.activity(child: child, authorID: author, now: now)
        let restored = try JSONDecoder().decode(Activity.self, from: JSONEncoder().encode(saved))
        #expect(restored.importIdentity == ImportIdentity(source: "example", id: "original-1"))
        let changed = try parse(input.replacingOccurrences(of: "60", with: "90").replacingOccurrences(of: "75", with: "105"))
        let review = CareImportDraft.excludingDuplicates(changed, existing: [restored], child: child, authorID: author)
        #expect(!review[0].included && review[0].importIssue != nil)
        #expect(throws: LogError.self) { try review[0].activity(child: child, authorID: author, now: now) }
        let sibling = ChildProfile(familyID: child.familyID, name: "Sibling")
        #expect(CareImportDraft.excludingDuplicates(changed, existing: [saved], child: sibling, authorID: author)[0].included)
        let otherSource = try parse(input.replacingOccurrences(of: "example", with: "other").replacingOccurrences(of: "08:30", with: "10:30"))
        #expect(CareImportDraft.excludingDuplicates(otherSource, existing: [saved], child: child, authorID: author)[0].included)
        let repeated = CareImportDraft.excludingDuplicates(try parse(input + "\n" + input), existing: [], child: child, authorID: author)
        #expect(repeated.map(\.included) == [true, false])
        #expect(repeated[0].id != repeated[1].id)
    }
    @Test func optionalIdentitiesAndLegacyRecordsRemainCompatible() throws {
        let row = try parse(JSONLinesCareImport.example)[0]
        let activity = try row.activity(child: child, authorID: author, now: now)
        let old = try JSONDecoder().decode(Activity.self, from: JSONEncoder().encode(activity))
        #expect(old.importIdentity == nil)
        #expect(!CareImportDraft.excludingDuplicates(try parse(JSONLinesCareImport.example), existing: [old], child: child, authorID: author)[0].included)
        let withID = try parse(replacing(#""notes":"Finished bottle.""#, with: #""id":"1""#))[0]
        #expect(withID.importIdentity?.source == "jsonl")
        for fields in [#""id":"""#, #""id":"1","source":" ""#, #""source":"example""#] {
            #expect(throws: LogError.self) { try parse(replacing(#""notes":"Finished bottle.""#, with: fields)) }
        }
    }
    @Test func fullBatchAndSizeLimitsApplyBeforeDecoding() throws {
        let lines = (0..<84).map { JSONLinesCareImport.example.replacingOccurrences(of: #""notes":"Finished bottle.""#, with: "\"id\":\"\($0)\"") }
        #expect(try parse(lines.joined(separator: "\n")).count == 84)
        #expect(throws: LogError.self) { try parse("{" + String(repeating: " ", count: CareNoteParser.maximumCharacters)) }
        #expect(throws: LogError.self) { try parse("{" + String(repeating: "\n", count: CareNoteParser.maximumLines)) }
    }
}
