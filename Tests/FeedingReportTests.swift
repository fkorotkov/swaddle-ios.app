import Foundation
import Testing
@testable import LittleLogCore

struct FeedingReportTests {
    @Test func reportIncludesUnknownVolumesWithoutAssigningThemToMilkOrFormula() {
        let fixture = LogRulesTests()
        var (snapshot, child) = fixture.fixture()
        for bottle in [Bottle(milkML: 60, formulaML: 15, unit: .ml), Bottle(milkML: 0, formulaML: 0, unit: .ml, unclassifiedML: 95)] {
            let activity = fixture.activity(child, payload: .bottle(bottle))
            let revision = RecordRevision(id: UUID(), recordID: activity.id, parentIDs: [], value: .activity(activity), date: fixture.now, editorID: fixture.personID, deleted: false)
            snapshot.records.append(ProjectedRecord(revision: revision, heads: [revision]))
        }
        let report = FeedingReport(child: child, period: .last24Hours, snapshot: snapshot, now: fixture.now)
        #expect(report.summary.totalML == 170 && report.summary.bottles == 2)
        #expect(report.summary.milkML == 60 && report.summary.formulaML == 15 && report.summary.unknownML == 95)
        #expect(report.spoken(unit: .ml).contains("170 mL recorded"))
        #expect(report.spoken(unit: .ml).contains("95 mL has an unrecorded milk/formula split"))
    }
    @Test func handsFreeResumeAndSwitchPreservePausedSide() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var session = Nursing(caregiverID: UUID())
        session.start(.right, at: start)
        session.pause(at: start.addingTimeInterval(60))
        session = try JSONDecoder().decode(Nursing.self, from: JSONEncoder().encode(session))
        session.resume(at: start.addingTimeInterval(120))
        #expect(session.activeSide == .right)
        session.pause(at: start.addingTimeInterval(180))
        session.switchSide(at: start.addingTimeInterval(240))
        #expect(session.activeSide == .left)
        #expect(session.duration(at: start.addingTimeInterval(300)) == 180)
    }
    @Test func reportSeparatesRecordedBottleIntakeFromSiblingPumpingAndNursing() {
        let fixture = LogRulesTests()
        var (snapshot, child) = fixture.fixture()
        let sibling = ChildProfile(familyID: child.familyID, name: "Jamie")
        var nursing = Nursing(caregiverID: fixture.personID)
        nursing.start(.left, at: fixture.now.addingTimeInterval(-1200))
        nursing.pause(at: fixture.now.addingTimeInterval(-600)); nursing.finished = true
        let values: [RecordValue] = [
            .child(sibling),
            .activity(fixture.activity(child, payload: .bottle(Bottle(milkML: 90, formulaML: 30, unit: .ml)))),
            .activity(fixture.activity(sibling, payload: .bottle(Bottle(milkML: 900, formulaML: 300, unit: .ml)))),
            .activity(fixture.activity(child, payload: .nursing(nursing), date: fixture.now.addingTimeInterval(-1200))),
            .pumping(PumpSession(familyID: child.familyID, motherID: fixture.personID, occurredAt: fixture.now, authorID: fixture.personID, totalML: 105, unit: .ml))
        ]
        for value in values {
            let revision = RecordRevision(id: UUID(), recordID: value.id, parentIDs: [], value: value, date: fixture.now, editorID: fixture.personID, deleted: false)
            snapshot.records.append(ProjectedRecord(revision: revision, heads: [revision]))
        }
        let report = FeedingReport(child: child, period: .last24Hours, snapshot: snapshot, now: fixture.now)
        #expect(report.summary.totalML == 120 && report.summary.milkML == 90 && report.summary.formulaML == 30)
        #expect(report.summary.bottles == 1 && report.summary.nursingSeconds == 600)
        #expect(report.spoken(unit: .oz).contains("4 oz"))
        #expect(report.spoken(unit: .ml).contains("10 minutes"))
        #expect(report.spoken(unit: .ml).contains("isn’t converted to volume"))
    }
    @Test func calendarReportWindowsIncludeMidnightOnceAndRespectDST() {
        let now = ISO8601DateFormatter().date(from: "2026-11-02T17:00:00Z")!
        let zone = TimeZone(identifier: "America/New_York")!
        let prior = ReportPeriod.yesterday.window(now: now, timeZone: zone)
        let today = ReportPeriod.today.window(now: now, timeZone: zone)
        #expect(prior.end.timeIntervalSince(prior.start) == 90000)
        let midnight = ISO8601DateFormatter().date(from: "2026-11-02T05:00:00Z")!
        #expect(midnight > today.start && midnight > prior.end)
        #expect(ReportPeriod.last24Hours.window(now: now, timeZone: zone).start == now.addingTimeInterval(-86400))
    }
}
