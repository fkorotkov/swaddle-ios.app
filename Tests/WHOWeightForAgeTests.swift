import Foundation
import Testing

@testable import LittleLogCore

struct WHOWeightForAgeTests {
  var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "America/New_York")!
    return value
  }
  func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
  func child(
    born: String = "2026-09-01T00:00:00-04:00", gestation: Int? = nil,
    sex: GrowthReferenceSex? = .male
  ) -> ChildProfile {
    ChildProfile(
      familyID: UUID(), name: "Robin", birthDate: date(born),
      gestationalAgeAtBirthDays: gestation, growthReferenceSex: sex)
  }

  @Test(arguments: whoWeightReferenceFixtures)
  func matchesIndependentPublishedCentiles(_ sample: WHOWeightReferenceFixture) throws {
    let percentile = try #require(
      WHOWeightForAge.percentile(
        kilograms: sample.kilograms, ageDays: sample.day, sex: sample.sex))
    // WHO rounds these reference weights to a gram; retain a strict but realistic tolerance.
    #expect(abs(percentile - sample.percentile) < 0.08)
    if [3.0, 50, 97].contains(sample.percentile) {
      let z =
        sample.percentile == 50
        ? 0 : sample.percentile == 3 ? -1.8807936081512509 : 1.8807936081512509
      let curveKG = try #require(
        WHOWeightForAge.kilograms(zScore: z, ageDays: sample.day, sex: sample.sex))
      #expect(abs(curveKG - sample.kilograms) <= 0.00051)
    }
  }

  @Test func usesMeasurementAgeAndKeepsAppearanceIndependent() throws {
    var child = child()
    child.gender = .girl
    let reading = try WHOWeightForAge.evaluate(
      grams: 3346.4, child: child, at: date("2026-09-01T23:00:00-04:00"),
      calendar: calendar, now: date("2026-10-10T12:00:00-04:00"))
    #expect(abs(reading.percentile - 50) < 0.00001)
    #expect(reading.age.days == 0)
    #expect(reading.reference == .male)
    child.growthReferenceSex = .female
    let girls = try WHOWeightForAge.evaluate(
      grams: 3346.4, child: child, at: date("2026-09-01T23:00:00-04:00"),
      calendar: calendar, now: date("2026-10-10T12:00:00-04:00"))
    #expect(girls.percentile > reading.percentile)
    #expect(girls.reference == .female)
  }

  @Test func legacyProfilesUseGenderWithoutRewritingTheirStoredReference() throws {
    let original: [String: Any] = [
      "id": UUID().uuidString, "familyID": UUID().uuidString,
      "name": "Robin", "gender": "boy",
    ]
    var legacy = try JSONDecoder().decode(
      ChildProfile.self, from: JSONSerialization.data(withJSONObject: original))
    #expect(legacy.growthReferenceSex == nil)
    #expect(legacy.colorTheme == nil)
    #expect(legacy.effectiveGrowthReferenceSex == .male)
    #expect(legacy.paletteGender == .boy)
    let event = date("2026-09-02T12:00:00-04:00")
    legacy.birthDate = date("2026-09-01T00:00:00-04:00")
    let reading = try WHOWeightForAge.evaluate(
      grams: 4000, child: legacy, at: event, calendar: calendar, now: event)
    #expect(reading.reference == .male)
    #expect(throws: WHOWeightForAge.Unavailable.missingReference) {
      try WHOWeightForAge.evaluate(
        grams: 4000, child: child(sex: nil), at: event, calendar: calendar, now: event)
    }
    var unknown = child()
    unknown.birthDate = nil
    #expect(throws: WHOWeightForAge.Unavailable.missingBirthDate) {
      try WHOWeightForAge.evaluate(
        grams: 4000, child: unknown, at: event, calendar: calendar, now: event)
    }
  }

  @Test func appearanceCannotChangeAutomaticOrExplicitGrowthReference() throws {
    var profile = child(sex: nil)
    profile.gender = .boy
    let event = date("2026-09-02T12:00:00-04:00")
    func reading() throws -> WHOWeightForAge.Reading {
      try WHOWeightForAge.evaluate(grams: 4000, child: profile, at: event, calendar: calendar, now: event)
    }
    let boys = try reading()
    for theme in ChildColorTheme.allCases {
      profile.colorTheme = theme
      #expect(try reading().percentile == boys.percentile)
      #expect(profile.effectiveGrowthReferenceSex == .male)
    }
    profile.gender = .girl
    #expect(try reading().reference == .female)
    profile.growthReferenceSex = .male
    #expect(try reading().percentile == boys.percentile)
    profile.gender = nil
    #expect(try reading().reference == .male)
    profile.growthReferenceSex = nil
    #expect(throws: WHOWeightForAge.Unavailable.missingReference) { try reading() }
  }

  @Test func pretermUsesCorrectedAgeFromTheDueDate() throws {
    let child = child(born: "2026-01-01T00:00:00-05:00", gestation: 35 * 7 + 4)
    let before = calendar.date(byAdding: .day, value: 30, to: child.birthDate!)!
    let start = calendar.date(byAdding: .day, value: 31, to: child.birthDate!)!
    #expect(throws: WHOWeightForAge.Unavailable.correctedAgeNotStarted) {
      try WHOWeightForAge.referenceAge(child: child, at: before, calendar: calendar, now: start)
    }
    let age = try WHOWeightForAge.referenceAge(child: child, at: start, calendar: calendar, now: start)
    #expect(age.chronologicalDays == 31 && age.days == 0 && age.isCorrected)
    let median = try #require(WHOWeightForAge.coefficients(ageDays: 0, sex: .male)).m
    let reading = try WHOWeightForAge.evaluate(grams: median * 1000, child: child,
      at: start, calendar: calendar, now: start)
    #expect(abs(reading.percentile - 50) < 0.00001)
    #expect(reading.context.contains("Corrected age"))
  }

  @Test(arguments: [nil, 37 * 7, 40 * 7, 42 * 7])
  func termOrUnknownGestationUsesChronologicalAge(_ gestation: Int?) throws {
    let child = child(gestation: gestation)
    let event = date("2026-09-10T23:00:00-04:00")
    let age = try WHOWeightForAge.referenceAge(
      child: child, at: event, calendar: calendar, now: event)
    #expect(age.days == 9)
    #expect(!age.isCorrected)
  }

  @Test func exactSecondBirthdayStopsComparisonIncludingLeapYears() throws {
    for born in ["2024-02-28T00:00:00-05:00", "2025-02-28T00:00:00-05:00"] {
      let child = child(born: born)
      let birthday = calendar.date(byAdding: .year, value: 2, to: child.birthDate!)!
      let lastDay = calendar.date(byAdding: .day, value: -1, to: birthday)!
      let last = try WHOWeightForAge.evaluate(
        grams: 11000, child: child, at: lastDay, calendar: calendar, now: birthday)
      #expect(last.percentile.isFinite)
      #expect(throws: WHOWeightForAge.Unavailable.ageOutsideRange) {
        try WHOWeightForAge.evaluate(
          grams: 11000, child: child, at: birthday, calendar: calendar, now: birthday)
      }
    }
  }

  @Test func invalidMeasurementsNeverInventPercentiles() throws {
    let now = date("2026-09-10T00:00:00-04:00")
    let child = child()
    for grams in [0, -1, Double.nan, Double.infinity] {
      #expect(throws: WHOWeightForAge.Unavailable.invalidWeight) {
        try WHOWeightForAge.evaluate(
          grams: grams, child: child, at: now, calendar: calendar, now: now)
      }
    }
    #expect(throws: WHOWeightForAge.Unavailable.futureMeasurement) {
      try WHOWeightForAge.evaluate(
        grams: 4000, child: child, at: now.addingTimeInterval(1), calendar: calendar, now: now)
    }
    #expect(throws: WHOWeightForAge.Unavailable.beforeBirth) {
      try WHOWeightForAge.evaluate(
        grams: 4000, child: child, at: date("2026-08-31T23:59:00-04:00"), calendar: calendar,
        now: now)
    }
    #expect(WHOWeightForAge.percentile(kilograms: 4, ageDays: -1, sex: .male) == nil)
    #expect(WHOWeightForAge.percentile(kilograms: 4, ageDays: 732, sex: .female) == nil)
    var invalid = child
    invalid.gestationalAgeAtBirthDays = Int.max
    #expect(throws: WHOWeightForAge.Unavailable.invalidGestation) {
      try WHOWeightForAge.referenceAge(child: invalid, at: now, calendar: calendar, now: now)
    }
  }

  @Test func familyCalendarHandlesDSTAndMeasurementsAroundMidnight() throws {
    let child = child(born: "2026-03-07T00:00:00-05:00")
    let first = date("2026-03-08T23:59:00-04:00")
    let next = date("2026-03-09T00:01:00-04:00")
    #expect(
      try WHOWeightForAge.referenceAge(child: child, at: first, calendar: calendar, now: next).days
        == 1)
    #expect(
      try WHOWeightForAge.referenceAge(child: child, at: next, calendar: calendar, now: next).days
        == 2)
  }

  @Test func extremePercentilesNeverLookLikeZeroOrHundred() {
    #expect(WHOWeightForAge.label(for: 0.001) == "Below 1st percentile")
    #expect(WHOWeightForAge.label(for: 99.999) == "Above 99th percentile")
    #expect(!WHOWeightForAge.label(for: 98.9).contains("100"))
    #expect(WHOWeightForAge.label(for: 50).contains("50"))
  }

  @Test func seriesPreservesTwoSameDayWeightsAndFiltersSiblings() throws {
    let child = child()
    let start = date("2026-09-10T00:00:00-04:00")
    let end = date("2026-09-11T00:00:00-04:00")
    func event(_ hours: Double, _ childID: UUID, grams: Decimal) -> Activity {
      Activity(
        familyID: child.familyID, childID: childID,
        occurredAt: start.addingTimeInterval(hours * 3600),
        authorID: UUID(), payload: .weight(grams: grams, unit: "kg"))
    }
    let first = event(8, child.id, grams: 3500)
    let last = event(18, child.id, grams: 3560)
    let series = WeightGrowthSeries(
      entries: [last, event(4, UUID(), grams: 6000), first], child: child,
      interval: DateInterval(start: start, end: end), calendar: calendar, now: end)
    #expect(series.measurements.map(\.id) == [first.id, last.id])
    #expect(series.measurements.allSatisfy { $0.reading?.age.days == 9 })
    #expect(series.curves.count == 3)
    #expect(series.curves.first?.points.last?.date == end)
    #expect(
      ChartSelection.measurement(near: last.occurredAt, among: series.measurements.map(\.date))
        == last.occurredAt)
    var missing = child
    missing.growthReferenceSex = nil
    let raw = WeightGrowthSeries(
      entries: [first], child: missing, interval: DateInterval(start: start, end: end),
      calendar: calendar, now: end)
    #expect(raw.measurements.count == 1)
    #expect(raw.measurements.first?.reading == nil)
    #expect(raw.curves.isEmpty)
  }
}
