import Foundation
import Testing
@testable import LittleLogCore

struct JSONLinesPumpImportTests {
    let mother = Caregiver(familyID: UUID(), name: "Alex", isMother: true)
    let author = UUID()
    let now = ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")!
    func changed(_ from: String, _ to: String) -> String { JSONLinesPumpImport.example.replacingOccurrences(of: from, with: to) }

    @Test func totalOnlyExportPreservesExactAmountsAndUnknownValues() throws {
        let source = String(JSONLinesPumpImport.totalOnlyExample.dropLast()) + #", "source":"example","id":"original-1","notes":"3.5 oz total.\nCaregiver observation."}"#
        let row = try JSONLinesPumpImport.parse(source)[0]
        let session = try row.session(mother: mother, authorID: author, now: now)
        #expect(session.totalML == Decimal(string: "103.50735346875"))
        #expect(session.leftML == nil && session.rightML == nil && session.minutes == nil)
        #expect(session.motherID == mother.id && session.authorID == author && session.unit == .ml)
        #expect(session.note.hasPrefix("3.5 oz total.\nCaregiver observation."))
        #expect(session.note.contains("Original JSON: " + source))
        #expect(session.importIdentity == ImportIdentity(source: "example", id: "original-1"))
        let restored = try JSONDecoder().decode(PumpSession.self, from: JSONEncoder().encode(session))
        #expect(restored == session)
    }

    @Test func knownSplitAndDurationAreValidatedWithoutLosingPrecision() throws {
        let row = try JSONLinesPumpImport.parse(changed(#""totalML":105"#, #""totalML":105.01"#))[0]
        let session = try row.session(mother: mother, authorID: author, now: now)
        #expect(session.totalML == 105 && session.leftML == 60 && session.rightML == 45 && session.minutes == 15)
        for (from, to) in [
            (#""totalML":105"#, #""totalML":106"#),
            (#""leftML":60"#, #""leftML":-60"#),
            (#""leftML":60"#, #""leftML":null"#),
            (#""rightML":45,"#, ""),
            (#""durationMinutes":15"#, #""durationMinutes":0"#),
            (#""durationMinutes":15"#, #""durationMinutes":-1"#)
        ] { #expect(throws: LogError.self) { try JSONLinesPumpImport.parse(changed(from, to)) } }
    }

    @Test func optionalSideAndDurationFieldsCanBeOmitted() throws {
        let minimal = #"{"type":"pump","version":1,"occurredAt":"2026-05-10T08:30:00-04:00","totalML":75}"#
        let row = try JSONLinesPumpImport.parse(minimal)[0]
        #expect(row.left.isEmpty && row.right.isEmpty && row.duration.isEmpty)
        #expect(try row.session(mother: mother, authorID: author, now: now).totalML == 75)
    }

    @Test func recognizesPumpingAndKeepsPhysicalLineNumbers() throws {
        let text = "\u{feff} \r\n\r\n\(JSONLinesPumpImport.example)\r\n\r\n\(JSONLinesPumpImport.totalOnlyExample)\r\n"
        #expect(JSONLinesPumpImport.recognizes(text))
        #expect(!JSONLinesPumpImport.recognizes(JSONLinesCareImport.example))
        #expect(!JSONLinesPumpImport.recognizes("Pumped 3 oz"))
        let rows = try JSONLinesPumpImport.parse(text)
        #expect(rows.count == 2 && rows.map(\.sourceLine) == [3, 5])
        for bad in ["{bad}", JSONLinesCareImport.example, "null", "[]"] {
            do { _ = try JSONLinesPumpImport.parse(JSONLinesPumpImport.example + "\n\n" + bad); Issue.record("Expected rejection") }
            catch { #expect(error.localizedDescription.contains("Line 3:")) }
        }
    }

    @Test func rejectsUnsupportedFieldsAndInvalidNumbers() throws {
        for (from, to) in [
            (#""version":1"#, #""version":2"#),
            (#""totalML":105,"#, ""),
            (#""notes""#, #""caregiver""#),
            (#""totalML":105"#, #""totalML":"105""#),
            (#""totalML":105"#, #""totalML":true"#),
            (#""totalML":105"#, #""totalML":0"#),
            (#""totalML":105"#, #""totalML":-1"#),
            (#""totalML":105"#, #""totalML":1e999"#),
            (#""durationMinutes":15"#, #""durationMinutes":"15""#),
            (#""id":"pump-123""#, #""id":" ""#),
            (#""source":"example-app""#, #""source":" ""#),
            (",\"id\":\"pump-123\"", "")
        ] {
            #expect(throws: LogError.self) { try JSONLinesPumpImport.parse(changed(from, to)) }
        }
    }

    @Test func missingTotalCanBeCalculatedOnlyFromBothRecordedSides() throws {
        let input = changed(#""totalML":105"#, #""totalML":null"#)
        let row = try JSONLinesPumpImport.parse(input)[0]
        #expect(row.total == "105" && row.reviewReason != nil)
        let session = try row.session(mother: mother, authorID: author, now: now)
        #expect(session.totalML == 105 && session.leftML == 60 && session.rightML == 45)
        for invalid in [input.replacingOccurrences(of: #""leftML":60"#, with: #""leftML":null"#),
                        JSONLinesPumpImport.totalOnlyExample.replacingOccurrences(of: "103.50735346875", with: "null")] {
            #expect(throws: LogError.self) { try JSONLinesPumpImport.parse(invalid) }
        }
    }

    @Test func explicitTimeZonesAndFutureDatesAreChecked() throws {
        let text = changed(#""notes":"Morning session.""#, #""timezone":"America/New_York""#)
        let row = try JSONLinesPumpImport.parse(text)[0]
        #expect(row.timeZoneIdentifier == "America/New_York")
        #expect(row.occurredAt == ISO8601DateFormatter().date(from: "2026-05-10T12:30:00Z"))
        #expect(throws: LogError.self) { try JSONLinesPumpImport.parse(text.replacingOccurrences(of: "America/New_York", with: "Asia/Tokyo")) }
        for date in ["2026-05-10T08:30:00", "2026-02-30T08:30:00Z", "2026-05-10T25:00:00Z"] {
            #expect(throws: LogError.self) { try JSONLinesPumpImport.parse(changed("2026-05-10T08:30:00-04:00", date)) }
        }
        let future = try JSONLinesPumpImport.parse(changed("2026-05-10", "2999-05-10"))[0]
        #expect(throws: LogError.self) { try future.session(mother: mother, authorID: author, now: now) }
    }

    @Test func duplicateIDsAreScopedToCaregiverAndNeverOverwrite() throws {
        let rows = try JSONLinesPumpImport.parse(JSONLinesPumpImport.example)
        let saved = try rows[0].session(mother: mother, authorID: author, now: now)
        let changedRows = try JSONLinesPumpImport.parse(changed(#""durationMinutes":15"#, #""durationMinutes":20"#))
        let review = PumpImportDraft.excludingDuplicates(changedRows, existing: [saved], mother: mother, authorID: author)
        #expect(!review[0].included && review[0].duplicateIdentity)
        #expect(throws: LogError.self) { try review[0].session(mother: mother, authorID: author, now: now) }
        let another = Caregiver(familyID: mother.familyID, name: "Sam", isMother: true)
        #expect(PumpImportDraft.excludingDuplicates(rows, existing: [saved], mother: another, authorID: author)[0].included)
        let repeated = PumpImportDraft.excludingDuplicates(try JSONLinesPumpImport.parse(JSONLinesPumpImport.example + "\n" + JSONLinesPumpImport.example), existing: [], mother: mother, authorID: author)
        #expect(repeated.map(\.included) == [true, false])
        #expect(repeated[1].duplicateIdentity)
    }

    @Test func similarTimesAndTotalsStartDeselectedButCanBeIncluded() throws {
        let rows = try JSONLinesPumpImport.parse(JSONLinesPumpImport.totalOnlyExample)
        let saved = try rows[0].session(mother: mother, authorID: author, now: now)
        var review = PumpImportDraft.excludingDuplicates(rows, existing: [saved], mother: mother, authorID: author)
        #expect(!review[0].included && !review[0].duplicateIdentity)
        review[0].included = true
        #expect(try review[0].session(mother: mother, authorID: author, now: now).totalML == saved.totalML)
    }

    @Test func legacySessionsDecodeWithoutImportMetadata() throws {
        let saved = PumpSession(familyID: mother.familyID, motherID: mother.id, occurredAt: now, authorID: author, totalML: 90, unit: .ml)
        let json = try JSONEncoder().encode(saved)
        #expect(!String(decoding: json, as: UTF8.self).contains("importIdentity"))
        let restored = try JSONDecoder().decode(PumpSession.self, from: json)
        #expect(restored == saved && restored.importIdentity == nil && restored.timeZoneIdentifier == nil)
    }

    @Test func limitsAndInvalidReviewEditsBlockSaving() throws {
        #expect(throws: LogError.self) { try JSONLinesPumpImport.parse(String(repeating: "\n", count: 501)) }
        #expect(throws: LogError.self) { try JSONLinesPumpImport.parse(String(repeating: "x", count: 50_001)) }
        var row = try JSONLinesPumpImport.parse(JSONLinesPumpImport.totalOnlyExample)[0]
        row.total = "-1"
        #expect(throws: LogError.self) { try row.session(mother: mother, authorID: author, now: now) }
        row.total = "100"; row.left = "30"
        #expect(throws: LogError.self) { try row.session(mother: mother, authorID: author, now: now) }
        row.left = ""; row.duration = "no"
        #expect(throws: LogError.self) { try row.session(mother: mother, authorID: author, now: now) }
        row.duration = ""
        var nonPumping = mother; nonPumping.isMother = false
        #expect(throws: LogError.self) { try row.session(mother: nonPumping, authorID: author, now: now) }
    }
}
