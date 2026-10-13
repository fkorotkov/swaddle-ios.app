import Foundation
import Testing

@testable import LittleLogCore

struct RecentCareTests {
  let familyID = UUID()
  let caregiverID = UUID()
  let now = Date(timeIntervalSince1970: 1_790_000_000)

  func revision(_ value: RecordValue, deleted: Bool = false) -> RecordRevision {
    .init(
      id: UUID(), recordID: value.id, parentIDs: [], value: value, date: now, editorID: caregiverID,
      deleted: deleted)
  }

  func snapshot(_ revisions: [RecordRevision]) -> FamilySnapshot {
    FamilySnapshot(
      family: Family(
        id: familyID, name: "Family", timeZoneIdentifier: "America/New_York", ownerID: caregiverID),
      records: RevisionProjection.project(revisions))
  }

  func feed(_ child: ChildProfile, at date: Date) -> Activity {
    Activity(
      familyID: familyID, childID: child.id, occurredAt: date, authorID: caregiverID,
      payload: .bottle(Bottle(milkML: 90, formulaML: 30, unit: .ml)))
  }

  func pump(at date: Date) -> PumpSession {
    PumpSession(
      familyID: familyID, motherID: caregiverID, occurredAt: date,
      authorID: UUID(), totalML: 150, unit: .ml)
  }

  @Test func interleavesPumpingByEventTimeWithoutChangingChildIntake() {
    let child = ChildProfile(familyID: familyID, name: "Robin")
    let first = feed(child, at: now.addingTimeInterval(-3600))
    let session = pump(at: now.addingTimeInterval(-1800))
    let latest = feed(child, at: now)
    let family = snapshot(
      [.child(child), .activity(first), .pumping(session), .activity(latest)].map { revision($0) })
    #expect(family.recentCare(for: child.id).map(\.id) == [latest.id, session.id, first.id])
    let summary = ActivitySummary(activities: family.activities, childID: child.id, end: now)
    #expect(summary.bottles == 2)
    #expect(summary.totalML == 240)
  }

  @Test func siblingsShareOneCaregiverSessionButKeepTheirOwnFeeds() {
    let child = ChildProfile(familyID: familyID, name: "Robin")
    let sibling = ChildProfile(familyID: familyID, name: "Jamie")
    let first = feed(child, at: now.addingTimeInterval(-60))
    let second = feed(sibling, at: now.addingTimeInterval(-60))
    let session = pump(at: now)
    let values: [RecordValue] = [
      .child(child), .child(sibling), .activity(first), .activity(second), .pumping(session),
    ]
    let family = snapshot(values.map { revision($0) })
    #expect(family.recentCare(for: child.id).map(\.id) == [session.id, first.id])
    #expect(family.recentCare(for: sibling.id).map(\.id) == [session.id, second.id])
    #expect(family.pumps.count == 1)
  }

  @Test func pumpingOnlyIsNotAnEmptyTimelineAndDoesNotFilterByAuthor() {
    let child = ChildProfile(familyID: familyID, name: "Robin")
    let session = pump(at: now)
    #expect(session.authorID != session.motherID)
    let family = snapshot([revision(.child(child)), revision(.pumping(session))])
    #expect(family.activities.isEmpty)
    #expect(family.recentCare(for: child.id) == [.pumping(session)])
  }

  @Test func foreignFamilyAndUnknownChildAreExcluded() {
    let child = ChildProfile(familyID: familyID, name: "Robin")
    var foreignPump = pump(at: now)
    foreignPump.familyID = UUID()
    var foreignFeed = feed(child, at: now)
    foreignFeed.familyID = UUID()
    let family = snapshot([
      revision(.child(child)), revision(.pumping(foreignPump)), revision(.activity(foreignFeed)),
    ])
    #expect(family.recentCare(for: child.id).isEmpty)
    #expect(family.recentCare(for: UUID()).isEmpty)
    #expect(FamilySnapshot().recentCare(for: child.id).isEmpty)
  }

  @Test func revisionsAppearOnceAndDeletedPumpingStaysHidden() {
    let child = ChildProfile(familyID: familyID, name: "Robin")
    var session = pump(at: now)
    let original = revision(.pumping(session))
    session.totalML = 180
    var edit = revision(.pumping(session))
    edit.parentIDs = [original.id]
    let childRevision = revision(.child(child))
    #expect(
      snapshot([childRevision, original, edit]).recentCare(for: child.id) == [.pumping(session)])
    var deletion = revision(.pumping(session), deleted: true)
    deletion.parentIDs = [original.id]
    let family = snapshot([childRevision, original, edit, deletion])
    #expect(family.record(session.id)?.hasConflict == true)
    #expect(family.recentCare(for: child.id).isEmpty)
  }

  @Test func equalTimesHaveDeterministicOrderAndPumpsParticipateInTheDisplayLimit() {
    let child = ChildProfile(familyID: familyID, name: "Robin")
    let session = pump(at: now)
    let feeds = (0..<110).map { feed(child, at: now.addingTimeInterval(-Double($0))) }
    let revisions =
      [revision(.child(child)), revision(.pumping(session))] + feeds.map { revision(.activity($0)) }
    let forward = snapshot(revisions).recentCare(for: child.id)
    let backward = snapshot(revisions.reversed()).recentCare(for: child.id)
    #expect(forward == backward)
    #expect(forward.count == 111)
    #expect(forward.prefix(100).contains(.pumping(session)))
    #expect(
      forward.prefix(2).map(\.id)
        == [feeds[0].id, session.id].sorted { $0.uuidString < $1.uuidString })
  }
}
