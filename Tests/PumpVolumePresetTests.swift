import Foundation
import Testing

@testable import LittleLogCore

struct PumpVolumePresetTests {
  let familyID = UUID()
  let caregiverID = UUID()
  let now = Date(timeIntervalSince1970: 1_790_000_000)

  func pump(minutesAgo: Double = 0, total: Decimal = 105) -> PumpSession {
    PumpSession(
      familyID: familyID, motherID: caregiverID,
      occurredAt: now.addingTimeInterval(-minutesAgo * 60), authorID: UUID(),
      totalML: total, unit: .ml)
  }

  func revision(_ session: PumpSession, deleted: Bool = false) -> RecordRevision {
    RecordRevision(
      id: UUID(), recordID: session.id, parentIDs: [], value: .pumping(session),
      date: now, editorID: session.authorID, deleted: deleted)
  }

  func snapshot(_ sessions: [RecordRevision]) -> FamilySnapshot {
    let caregiver = Caregiver(id: caregiverID, familyID: familyID, name: "Alex", isMother: true)
    let profile = RecordRevision(
      id: UUID(), recordID: caregiver.id, parentIDs: [], value: .caregiver(caregiver),
      date: now, editorID: caregiverID, deleted: false)
    return FamilySnapshot(
      family: Family(
        id: familyID, name: "Family", timeZoneIdentifier: "America/New_York", ownerID: caregiverID),
      records: RevisionProjection.project([profile] + sessions))
  }

  @Test func latestUsesEventTimeAndCaregiverRatherThanAuthorOrImportTime() {
    let recent = pump(minutesAgo: 30, total: 135)
    var imported = pump(minutesAgo: 120, total: 90)
    imported.createdAt = now.addingTimeInterval(60)
    var otherCaregiver = pump(total: 180)
    otherCaregiver.motherID = UUID()
    var otherFamily = pump(total: 200)
    otherFamily.familyID = UUID()
    let family = snapshot([recent, imported, otherCaregiver, otherFamily].map { revision($0) })
    #expect(recent.authorID != caregiverID)
    #expect(PumpVolumePreset.latest(for: caregiverID, in: family, now: now)?.session == recent)
  }

  @Test func unknownOrMissingPumpingProfileStartsBlank() {
    let family = snapshot([])
    #expect(PumpVolumePreset.latest(for: caregiverID, in: family, now: now) == nil)
    let withSession = snapshot([revision(pump())])
    #expect(PumpVolumePreset.latest(for: nil, in: withSession, now: now) == nil)
    #expect(PumpVolumePreset.latest(for: UUID(), in: withSession, now: now) == nil)
    #expect(PumpVolumePreset.latest(for: caregiverID, in: FamilySnapshot(), now: now) == nil)
    var removedProfile = withSession
    removedProfile.records.removeAll { $0.id == caregiverID }
    #expect(PumpVolumePreset.latest(for: caregiverID, in: removedProfile, now: now) == nil)
  }

  @Test func deletedConflictingFutureAndInvalidSessionsDoNotBecomeDefaults() {
    let valid = pump(minutesAgo: 60, total: 120)
    let conflicted = pump(minutesAgo: 10)
    let first = revision(conflicted)
    var conflictingEdit = conflicted
    conflictingEdit.totalML = 90
    let invalid = [pump(minutesAgo: -1), pump(total: -1), pump(total: 0), pump(total: .nan)]
    let family = snapshot(
      [revision(valid), revision(pump(), deleted: true), first, revision(conflictingEdit)]
        + invalid.map { revision($0) })
    #expect(PumpVolumePreset.latest(for: caregiverID, in: family, now: now)?.session.id == valid.id)
  }

  @Test func exactSideVolumesUseCurrentDisplayUnitAndKeepTheirPrecision() throws {
    var session = pump(total: Decimal(string: "103.51")!)
    session.leftML = Decimal(string: "59.15")!
    session.rightML = Decimal(string: "44.36")!
    let preset = PumpVolumePreset(session: session)
    #expect(preset.split)
    var draft = preset.draft(unit: .oz)
    #expect(draft.unit == .oz)
    #expect(draft.firstML == session.leftML && draft.secondML == session.rightML)
    draft.adjust(1, component: .first)
    draft.adjust(-1, component: .first)
    draft.changeUnit(.ml)
    let amounts = try draft.validated()
    #expect(amounts.0 + amounts.1 == session.totalML)
    #expect(draft.firstML == session.leftML && draft.secondML == session.rightML)
  }

  @Test func totalAndPartialSidesNeverInventAnUnrecordedSplit() {
    for sides: (Decimal?, Decimal?) in [(nil, nil), (60, nil), (nil, 45), (60, 30)] {
      var session = pump()
      session.leftML = sides.0
      session.rightML = sides.1
      let preset = PumpVolumePreset(session: session)
      #expect(!preset.split)
      let draft = preset.draft(unit: .ml)
      #expect(draft.firstML == 105 && draft.secondML == nil)
    }
  }

  @Test func editedSessionsUseLatestResolvedVolumeAndTiesStayDeterministic() {
    let original = pump()
    let first = revision(original)
    var edited = original
    edited.totalML = 150
    var second = revision(edited)
    second.parentIDs = [first.id]
    let family = snapshot([first, second])
    #expect(PumpVolumePreset.latest(for: caregiverID, in: family, now: now)?.session.totalML == 150)
    let tied = pump(total: 180)
    let records = [first, second, revision(tied)]
    #expect(
      PumpVolumePreset.latest(for: caregiverID, in: snapshot(records), now: now)?.session.id
        == PumpVolumePreset.latest(for: caregiverID, in: snapshot(records.reversed()), now: now)?
        .session.id)
  }
}
