import Foundation
import Testing
@testable import LittleLogCore

struct CareNoteImportTests {
    let zone = TimeZone(identifier: "America/New_York")!
    let firstDay = ISO8601DateFormatter().date(from: "2026-09-18T16:00:00Z")!
    let now = ISO8601DateFormatter().date(from: "2026-09-20T16:00:00Z")!
    @Test func nurseReportPreservesNotesAndFlagsAssumptionsAcrossMidnight() throws {
        let rows = try CareNoteParser.parse(CareNoteParser.sample, firstDay: firstDay, timeZone: zone, defaultUnit: .ml)
        #expect(rows.count == 7)
        let feeds = rows.filter { $0.kind == .bottle }
        #expect(feeds.map(\.milk) == ["2.5", "3", "2.5"])
        #expect(feeds.allSatisfy { $0.unit == .oz })
        #expect(feeds[0].reviewReasons.contains { $0.contains("fraction") })
        #expect(feeds[0].reviewReasons.contains { $0.contains("Unit missing") })
        #expect(feeds[1].reviewReasons.contains { $0.contains("midnight") })
        #expect(feeds[0].timestamp == ISO8601DateFormatter().date(from: "2026-09-19T03:28:00Z"))
        #expect(feeds[2].timestamp == ISO8601DateFormatter().date(from: "2026-09-19T10:00:00Z"))
        let diapers = rows.filter { $0.kind == .diaper }
        #expect(diapers.allSatisfy(\.pee) && diapers.filter(\.poo).count == 2)
        #expect(diapers.allSatisfy { $0.reviewReasons.contains { $0.contains("No time given") } })
        #expect(rows.first { $0.kind == .note }?.note == "He have a red mark on his cheek on both side think he’s getting baby acne")
        let child = ChildProfile(familyID: UUID(), name: "Robin")
        let entries = try rows.map { try $0.activity(child: child, authorID: UUID(), now: now) }
        let summary = ActivitySummary(activities: entries, childID: child.id, end: now)
        #expect(summary.totalML == VolumeUnit.oz.toML(8))
        #expect(summary.wet == 3 && summary.soiled == 2 && summary.changes == 3)
    }
    @Test func missingTimeNegationAndNegativeAmountsAreNeverSilentlyRecorded() throws {
        let child = ChildProfile(familyID: UUID(), name: "Robin")
        let rows = try CareNoteParser.parse("No pee overnight\n\nPee\n\nFeed formula 10 pm -3oz", firstDay: firstDay, timeZone: zone, defaultUnit: .ml)
        #expect(rows[0].kind == .note)
        #expect(rows[1].timestamp == nil)
        #expect(throws: LogError.self) { try rows[1].activity(child: child, authorID: UUID(), now: now) }
        #expect(rows[2].formula == "-3")
        #expect(throws: LogError.self) { try rows[2].activity(child: child, authorID: UUID(), now: now) }
    }
    @Test func fractionFormatsAndExplicitDatesRemainPrecise() throws {
        for text in ["2½", "2 1/2", "21/2", "2.5"] { #expect(CareNoteParser.amount(text)?.value == Decimal(string: "2.5")) }
        #expect(CareNoteParser.amount("1/2")?.value == Decimal(string: "0.5"))
        #expect(CareNoteParser.amount("1/0") == nil)
        for text in ["-0½", "-0 1/2", "-1/2"] { #expect(CareNoteParser.amount(text)?.value == Decimal(string: "-0.5")) }
        #expect(CareNoteParser.amount("-21/2")?.value == Decimal(string: "-2.5"))
        let rows = try CareNoteParser.parse("2026-09-18\n23:28 bm 2½ oz\n02:36 formula 130ml", firstDay: now, timeZone: zone, defaultUnit: .ml)
        #expect(rows.count == 2 && rows[0].milk == "2.5" && rows[1].formula == "130")
        #expect(rows[1].unit == .ml)
        #expect(throws: LogError.self) { try CareNoteParser.parse("2026-02-30\npee", firstDay: now, timeZone: zone, defaultUnit: .ml) }
    }
    @Test func nonexistentDSTTimeRequiresCorrectionAndPlannedFeedsStayNotes() throws {
        let gapDay = ISO8601DateFormatter().date(from: "2026-03-08T16:00:00Z")!
        let rows = try CareNoteParser.parse("Feed bm 2:30 am 3oz\nFeed bm 4 am 3oz\nWill feed bm 5 am 3oz", firstDay: gapDay, timeZone: zone, defaultUnit: .ml)
        #expect(rows[0].timestamp == nil)
        #expect(rows[0].reviewReasons.contains { $0.contains("doesn’t exist") })
        #expect(rows[2].kind == .note)
    }
    @Test func yesterdayUsesCalendarBoundariesAndEmptyFeedingReportsAreExplicit() throws {
        let window = ReportPeriod.yesterday.window(now: now, timeZone: zone)
        #expect(window.start < ISO8601DateFormatter().date(from: "2026-09-19T04:00:00Z")!)
        #expect(window.end < ISO8601DateFormatter().date(from: "2026-09-20T04:00:00Z")!)
        let fixture = LogRulesTests()
        let (snapshot, child) = fixture.fixture()
        let report = FeedingReport(child: child, period: .last24Hours, snapshot: snapshot, now: now)
        #expect(report.spoken(unit: .oz).contains("No bottle feeds recorded"))
    }
}
