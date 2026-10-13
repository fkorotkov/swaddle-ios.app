import Foundation
import Testing

@testable import BabyActivityRecorder

@MainActor
struct GrowthReferencePersistenceTests {
  @Test func lengthAndHeadMeasurementsReloadEditAndDeleteWithoutChangingOtherHistory() throws {
    let persistence = PersistenceController(inMemory: true)
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = LogStore(persistence: persistence, defaults: defaults, publishesWidgets: false)
    try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml)
    var child = try #require(store.selectedChild)
    child.birthDate = .now.addingTimeInterval(-40 * 86400); child.gender = .boy
    try store.save(.child(child))
    let length = Activity(familyID: child.familyID, childID: child.id, occurredAt: .now.addingTimeInterval(-60),
      authorID: store.caregiverID, note: "Clinic length", payload: .length(centimeters: 51, unit: .cm, position: .lyingDown))
    let head = Activity(familyID: child.familyID, childID: child.id, occurredAt: .now.addingTimeInterval(-120),
      authorID: store.caregiverID, payload: .headCircumference(centimeters: 35.56, unit: .inch))
    try store.save(.activity(length)); try store.save(.activity(head))
    let reloaded = LogStore(persistence: persistence, defaults: defaults, publishesWidgets: false)
    #expect(reloaded.snapshot.activities.contains(length) && reloaded.snapshot.activities.contains(head))
    var edited = length; edited.payload = .length(centimeters: 52, unit: .cm, position: .lyingDown)
    try reloaded.save(.activity(edited))
    #expect(reloaded.history(for: length.id).count == 2)
    #expect(reloaded.history(for: length.id).contains { $0.value == .activity(length) })
    try reloaded.delete(try #require(reloaded.snapshot.record(head.id)))
    let final = LogStore(persistence: persistence, defaults: defaults, publishesWidgets: false)
    #expect(final.snapshot.activities == [edited])
    #expect(final.history(for: head.id).contains { $0.deleted })
  }
  @Test func referenceIsSharedAndEditableWithoutRewritingWeightHistory() throws {
    let persistence = PersistenceController(inMemory: true)
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let store = LogStore(persistence: persistence, defaults: defaults, publishesWidgets: false)
    try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml)
    var child = try #require(store.selectedChild)
    child.birthDate = .now.addingTimeInterval(-21 * 86400)
    child.gender = .girl
    child.growthReferenceSex = .male
    child.colorTheme = .sage
    try store.save(.child(child))
    let weight = Activity(
      familyID: child.familyID, childID: child.id, occurredAt: .now.addingTimeInterval(-60),
      authorID: store.caregiverID, payload: .weight(grams: 3800, unit: "kg"))
    try store.save(.activity(weight))
    let reload = LogStore(persistence: persistence, defaults: defaults, publishesWidgets: false)
    #expect(reload.selectedChild?.growthReferenceSex == .male)
    #expect(reload.selectedChild?.gender == .girl)
    #expect(reload.selectedChild?.colorTheme == .sage)
    #expect(reload.selectedChild?.paletteGender == nil)
    let payload = try #require(reload.snapshot.record(child.id)?.revision.value)
    let roundTrip = try JSONDecoder().decode(
      RecordEnvelope.self, from: JSONEncoder().encode(RecordEnvelope(value: payload)))
    #expect(roundTrip.value == .child(child))
    child.growthReferenceSex = .female
    try reload.save(.child(child))
    reload.reload()
    #expect(reload.selectedChild?.growthReferenceSex == .female)
    #expect(reload.snapshot.activities == [weight])
    child.growthReferenceSex = nil
    try reload.save(.child(child))
    #expect(reload.selectedChild?.growthReferenceSex == nil)
    #expect(reload.selectedChild?.effectiveGrowthReferenceSex == .female)
    child.colorTheme = .blue
    try reload.save(.child(child))
    #expect(reload.selectedChild?.effectiveGrowthReferenceSex == .female)
    #expect(reload.selectedChild?.paletteGender == .boy)
    #expect(reload.snapshot.activities == [weight])
  }
}
