import Foundation
import Testing
@testable import LittleLogCore

struct WidgetCareSummaryTests {
    private let fixture = LogRulesTests()
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func put(_ value: RecordValue, in snapshot: inout FamilySnapshot, deleted: Bool = false) {
        let revision = RecordRevision(id: UUID(), recordID: value.id, parentIDs: [], value: value,
            date: now, editorID: fixture.personID, deleted: deleted)
        snapshot.records.removeAll { $0.id == value.id }
        snapshot.records.append(ProjectedRecord(revision: revision, heads: [revision]))
    }

    @Test func cachedSummarySeparatesChildIntakeFromAllFamilyPumping() throws {
        var (snapshot, child) = fixture.fixture()
        let sibling = ChildProfile(familyID: child.familyID, name: "Jamie")
        put(.child(sibling), in: &snapshot)
        put(.activity(fixture.activity(child, payload: .bottle(.init(milkML: 90, formulaML: 30, unit: .ml)), date: now)), in: &snapshot)
        put(.activity(fixture.activity(sibling, payload: .bottle(.init(milkML: 900, formulaML: 0, unit: .ml)), date: now)), in: &snapshot)
        for diaper in [Diaper(pee: true, poo: false), Diaper(pee: false, poo: true), Diaper(pee: true, poo: true)] {
            put(.activity(fixture.activity(child, payload: .diaper(diaper), date: now)), in: &snapshot)
        }
        var split = PumpSession(familyID: child.familyID, motherID: fixture.personID, occurredAt: now,
            authorID: UUID(), totalML: 180, leftML: 90, rightML: 90, unit: .ml, note: "Not needed by the widget")
        put(.pumping(split), in: &snapshot)
        split.id = UUID(); split.motherID = UUID(); split.totalML = 120
        put(.pumping(split), in: &snapshot)
        split.id = UUID(); split.familyID = UUID(); split.totalML = 1000
        put(.pumping(split), in: &snapshot)
        let cache = WidgetSnapshot.capture(snapshot, actorID: fixture.personID, canRecord: true, at: now)
        let data = try JSONEncoder().encode(cache)
        #expect(!String(decoding: data, as: UTF8.self).contains("Not needed by the widget"))
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        let target = try #require(decoded.children.first { $0.id == child.id })
        let summary = WidgetCareSummary(child: target, pumps: decoded.pumps, at: now)
        #expect(summary.activity.totalML == 120 && summary.activity.bottles == 1)
        #expect(summary.activity.changes == 3 && summary.activity.wet == 2 && summary.activity.soiled == 2)
        #expect(summary.pumpedML == 300 && summary.pumpingSessions == 2)
        #expect(WidgetCareSummary(child: try #require(decoded.children.first { $0.id == sibling.id }),
            pumps: decoded.pumps, at: now).pumpedML == 300)
    }

    @Test func pumpEditsDeletionsAndRollingWindowAreReflectedWithoutDoubleCounting() throws {
        var (snapshot, child) = fixture.fixture()
        let start = now.addingTimeInterval(-86400)
        for date in [start, start.addingTimeInterval(1), now, now.addingTimeInterval(1)] {
            put(.pumping(PumpSession(familyID: child.familyID, motherID: fixture.personID, occurredAt: date,
                authorID: fixture.personID, totalML: 60, unit: .ml)), in: &snapshot)
        }
        var edited = PumpSession(familyID: child.familyID, motherID: fixture.personID, occurredAt: now,
            authorID: fixture.personID, totalML: 30, unit: .ml)
        put(.pumping(edited), in: &snapshot)
        edited.totalML = 90
        put(.pumping(edited), in: &snapshot)
        var deleted = edited; deleted.id = UUID(); deleted.totalML = 1000
        put(.pumping(deleted), in: &snapshot, deleted: true)
        let cache = WidgetSnapshot.capture(snapshot, actorID: fixture.personID, canRecord: false, at: now)
        let target = try #require(cache.children.first)
        #expect(WidgetCareSummary(child: target, pumps: cache.pumps, at: now).pumpedML == 210)
        // At the exact next second the oldest event expires and the future event enters.
        #expect(WidgetCareSummary(child: target, pumps: cache.pumps, at: now.addingTimeInterval(1)).pumpedML == 210)
        #expect(WidgetCareSummary(child: target, pumps: cache.pumps, at: now.addingTimeInterval(86401)).pumpedML == 0)
        #expect(cache.canRecord == false)
    }

    @Test func oldCacheHasUnknownPumpingRatherThanAFalseZero() throws {
        let child = CachedChild(id: UUID(), familyID: UUID(), name: "Robin", activities: [])
        let legacy = WidgetSnapshot(asOf: now, children: [child])
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(legacy))
        #expect(decoded.pumps == nil)
        #expect(WidgetCareSummary(child: child, pumps: decoded.pumps, at: now).pumpedML == nil)
        #expect(WidgetCareSummary(child: child, pumps: [], at: now).pumpedML == 0)
    }

    @Test func timelineUpdatesAtExactEventAndUndoBoundaries() {
        let family = UUID(), childID = UUID(), actor = UUID()
        let expiration = now.addingTimeInterval(17)
        let oldBottle = Activity(familyID: family, childID: childID,
            occurredAt: expiration.addingTimeInterval(-86400), authorID: actor,
            payload: .bottle(.init(milkML: 90, formulaML: 0, unit: .ml)))
        let receipt = WidgetQuickLogReceipt(recordID: UUID(), createdAt: now.addingTimeInterval(-10))
        let child = CachedChild(id: childID, familyID: family, name: "Robin", activities: [oldBottle], quickLogs: ["both": receipt])
        let pump = CachedPumpSession(id: UUID(), familyID: family, occurredAt: now.addingTimeInterval(21), totalML: 150)
        let unrelated = CachedPumpSession(id: UUID(), familyID: UUID(), occurredAt: now.addingTimeInterval(22), totalML: 200)
        let dates = WidgetCareTimeline.dates(child: child, pumps: [pump, unrelated], from: now)
        #expect(dates.contains(expiration) && dates.contains(receipt.undoUntil) && dates.contains(pump.occurredAt))
        #expect(!dates.contains(unrelated.occurredAt))
        #expect(dates == Array(Set(dates)).sorted())
        #expect(dates.first == now && dates.last == now.addingTimeInterval(3600))
        #expect(WidgetCareSummary(child: child, pumps: [pump], at: expiration).activity.totalML == 0)
        #expect(WidgetCareSummary(child: child, pumps: [pump], at: pump.occurredAt).pumpedML == 150)
    }
}
