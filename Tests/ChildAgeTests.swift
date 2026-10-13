import Foundation
import Testing

@testable import LittleLogCore

struct ChildAgeTests {
  let familyID = UUID()

  var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "America/New_York")!
    return value
  }

  func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
  }

  func child(born: String, gestation: Int? = nil) -> ChildProfile {
    ChildProfile(
      familyID: familyID, name: "Robin", birthDate: date(born),
      gestationalAgeAtBirthDays: gestation)
  }

  @Test func legacyProfileDoesNotInventABirthdayOrGestation() throws {
    let payload: [String: Any] = [
      "id": UUID().uuidString, "familyID": familyID.uuidString, "name": "Robin",
    ]
    let child = try JSONDecoder().decode(
      ChildProfile.self, from: JSONSerialization.data(withJSONObject: payload))
    #expect(child.birthDate == nil)
    #expect(child.gestationalAgeAtBirthDays == nil)
    #expect(ChildAge(child: child, at: .now, calendar: calendar) == nil)
  }

  @Test func prematureBabyUsesDaysWithoutRoundingGestation() throws {
    let child = child(born: "2026-09-12T00:00:00-04:00", gestation: 35 * 7 + 4)
    let age = try #require(
      ChildAge(child: child, at: date("2026-10-09T17:00:00-04:00"), calendar: calendar))
    #expect(age.chronologicalDays == 27)
    #expect(age.chronologicalLabel == "3w 6d old")
    #expect(age.currentGestationalDays == 39 * 7 + 3)
    #expect(age.correctedDays == -4)
    #expect(age.correctedLabel == "Due in 4d")
    #expect(age.estimatedDueDate == date("2026-10-13T00:00:00-04:00"))
  }

  @Test(arguments: [
    ("2026-09-12T23:55:00-04:00", "2026-10-11T23:59:00-04:00", "4w 1d old", "4 weeks and 1 day"),
    ("2026-09-12T23:55:00-04:00", "2026-10-12T00:00:00-04:00", "1mo old", "1 month"),
    ("2026-09-12T00:00:00-04:00", "2026-10-16T12:00:00-04:00", "1mo 4d old", "1 month and 4 days"),
    ("2026-09-12T00:00:00-04:00", "2026-11-13T12:00:00-05:00", "2mo 1d old", "2 months and 1 day"),
    ("2026-01-31T00:00:00-05:00", "2026-02-27T23:59:00-05:00", "3w 6d old", "3 weeks and 6 days"),
    ("2026-01-31T00:00:00-05:00", "2026-02-28T00:00:00-05:00", "1mo old", "1 month"),
    ("2026-01-31T00:00:00-05:00", "2026-03-01T00:00:00-05:00", "1mo 1d old", "1 month and 1 day"),
    ("2024-01-31T00:00:00-05:00", "2024-02-29T00:00:00-05:00", "1mo old", "1 month"),
    ("2024-02-29T00:00:00-05:00", "2025-02-28T00:00:00-05:00", "12mo old", "12 months"),
    ("2026-03-07T00:00:00-05:00", "2026-04-08T00:00:00-04:00", "1mo 1d old", "1 month and 1 day"),
    ("2026-10-07T00:00:00-04:00", "2026-11-08T00:00:00-05:00", "1mo 1d old", "1 month and 1 day"),
    ("2026-10-01T00:30:00Z", "2026-10-31T04:00:00Z", "1mo 1d old", "1 month and 1 day"),
  ])
  func ageSwitchesToCalendarMonths(
    _ born: String, _ now: String, _ label: String, _ spoken: String
  ) throws {
    let age = try #require(ChildAge(child: child(born: born), at: date(now), calendar: calendar))
    #expect(age.chronologicalLabel == label)
    #expect(age.spokenChronologicalDuration == spoken)
  }

  @Test func correctedAgeTransitionsFromDueInToDueTodayToAge() throws {
    let child = child(born: "2026-09-01T00:00:00-04:00", gestation: 36 * 7)
    let before = try #require(
      ChildAge(child: child, at: date("2026-09-28T23:59:00-04:00"), calendar: calendar))
    let due = try #require(
      ChildAge(child: child, at: date("2026-09-29T00:00:00-04:00"), calendar: calendar))
    let after = try #require(
      ChildAge(child: child, at: date("2026-10-07T00:00:00-04:00"), calendar: calendar))
    #expect(before.correctedLabel == "Due in 1d")
    #expect(due.correctedLabel == "Due today")
    #expect(after.correctedLabel == "1w 1d")
    #expect(after.currentGestationalDays == 41 * 7 + 1)
  }

  @Test(arguments: [37 * 7, 39 * 7 + 6, 40 * 7, 42 * 7])
  func termBirthDoesNotApplyPrematurityCorrection(_ gestation: Int) throws {
    let child = child(born: "2026-09-01T00:00:00-04:00", gestation: gestation)
    let age = try #require(
      ChildAge(child: child, at: date("2026-09-08T12:00:00-04:00"), calendar: calendar))
    #expect(age.chronologicalDays == 7)
    #expect(age.currentGestationalDays == gestation + 7)
    #expect(age.correctedDays == nil)
  }

  @Test func calendarDaysSurviveDaylightSaving() throws {
    let child = child(born: "2026-03-07T23:55:00-05:00", gestation: 34 * 7)
    let now = date("2026-03-09T00:01:00-04:00")
    #expect(now.timeIntervalSince(child.birthDate!) < 24 * 3600)
    let age = try #require(ChildAge(child: child, at: now, calendar: calendar))
    #expect(age.chronologicalDays == 2)
    #expect(age.currentGestationalDays == 34 * 7 + 2)
    #expect(age.estimatedDueDate == date("2026-04-18T00:00:00-04:00"))
  }

  @Test func birthDayLeapDayAndUnknownGestationRemainUseful() throws {
    let child = child(born: "2024-02-28T00:00:00-05:00")
    let atBirth = try #require(
      ChildAge(child: child, at: date("2024-02-28T23:59:00-05:00"), calendar: calendar))
    let afterLeapDay = try #require(
      ChildAge(child: child, at: date("2024-03-01T00:00:00-05:00"), calendar: calendar))
    #expect(atBirth.chronologicalLabel == "Born today")
    #expect(afterLeapDay.chronologicalDays == 2)
    #expect(afterLeapDay.currentGestationalDays == nil)
    #expect(afterLeapDay.correctedDays == nil)
    #expect(afterLeapDay.estimatedDueDate == nil)
  }

  @Test func invalidProfileCannotBeSavedAndDoesNotShowFalseGestation() throws {
    let now = date("2026-09-20T00:00:00-04:00")
    for invalid in [-1, 0, 6, 46 * 7, Int.max] {
      let child = child(born: "2026-09-01T00:00:00-04:00", gestation: invalid)
      #expect(throws: LogError.self) { try child.validateBirthDetails(now: now) }
      #expect(ChildAge(child: child, at: now, calendar: calendar)?.currentGestationalDays == nil)
    }
    var withoutBirth = ChildProfile(familyID: familyID, name: "Robin")
    withoutBirth.gestationalAgeAtBirthDays = 35 * 7
    #expect(throws: LogError.self) { try withoutBirth.validateBirthDetails(now: now) }
    let future = child(born: "2026-09-21T00:00:00-04:00", gestation: 35 * 7)
    #expect(throws: LogError.self) { try future.validateBirthDetails(now: now) }
    #expect(ChildAge(child: future, at: now, calendar: calendar) == nil)
  }

  @Test func sharedProfileRoundTripPreservesExactBirthDetails() throws {
    let child = child(born: "2026-09-12T00:00:00-04:00", gestation: 35 * 7 + 4)
    let envelope = RecordEnvelope(value: .child(child))
    let decoded = try JSONDecoder().decode(
      RecordEnvelope.self, from: JSONEncoder().encode(envelope))
    #expect(decoded == envelope)
    #expect(decoded.version == 1)
    var updated = child
    updated.name = "Robin Rose"
    #expect(updated.gestationalAgeAtBirthDays == 249)
  }
}
