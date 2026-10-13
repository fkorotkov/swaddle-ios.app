import Foundation
import Testing

@testable import BabyActivityRecorder

@MainActor
struct ChildAgePersistenceTests {
  @Test func savesReloadsEditsAndClearsBirthDetailsWithoutChangingCareHistory() throws {
    let store = LogStore(
      persistence: PersistenceController(inMemory: true),
      defaults: UserDefaults(suiteName: UUID().uuidString)!, publishesWidgets: false)
    try store.createFamily(childName: "Robin", caregiverName: "Sam", mother: false, unit: .ml)
    var child = try #require(store.selectedChild)
    child.birthDate = Date.now.addingTimeInterval(-21 * 86400)
    child.gestationalAgeAtBirthDays = 35 * 7 + 4
    try store.save(.child(child))
    let sibling = ChildProfile(familyID: child.familyID, name: "Jamie")
    try store.save(.child(sibling))
    let bottle = Activity(
      familyID: child.familyID, childID: child.id, occurredAt: .now.addingTimeInterval(-60),
      authorID: store.caregiverID,
      payload: .bottle(Bottle(milkML: 120, formulaML: 0, unit: .ml)))
    try store.save(.activity(bottle))
    store.reload()
    #expect(store.selectedChild?.gestationalAgeAtBirthDays == 249)
    #expect(
      store.snapshot.children.first(where: { $0.id == sibling.id })?.gestationalAgeAtBirthDays
        == nil)

    child.name = "Robin Rose"
    try store.save(.child(child))
    #expect(store.selectedChild?.gestationalAgeAtBirthDays == 249)
    var invalid = child
    invalid.gestationalAgeAtBirthDays = -1
    #expect(throws: LogError.self) { try store.save(.child(invalid)) }
    #expect(store.selectedChild?.gestationalAgeAtBirthDays == 249)

    child.birthDate = nil
    child.gestationalAgeAtBirthDays = nil
    try store.save(.child(child))
    store.reload()
    #expect(store.selectedChild?.birthDate == nil)
    #expect(store.selectedChild?.gestationalAgeAtBirthDays == nil)
    #expect(store.snapshot.activities == [bottle])
    #expect(store.history(for: child.id).count == 4)
  }
}
