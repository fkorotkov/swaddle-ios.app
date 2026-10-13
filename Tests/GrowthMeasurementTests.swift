import Foundation
import Testing
@testable import LittleLogCore

struct GrowthMeasurementTests {
  private var calendar: Calendar {
    var result = Calendar(identifier: .gregorian)
    result.timeZone = TimeZone(identifier: "America/New_York")!
    return result
  }
  private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
  private func child(sex: GrowthReferenceSex? = .male, gestation: Int? = nil) -> ChildProfile {
    ChildProfile(familyID: UUID(), name: "Robin", birthDate: date("2026-09-01T12:00:00-04:00"),
      gestationalAgeAtBirthDays: gestation, growthReferenceSex: sex)
  }

  @Test func matchesIndependentWHOPublishedCentilesForBothMeasurementsAndSexes() throws {
    for fixture in whoMeasurementFixtures {
      let p = try #require(MeasurementForAge.whoPercentile(centimeters: fixture.centimeters,
        metric: fixture.metric, ageDays: fixture.day, sex: fixture.sex))
      #expect(abs(p - fixture.percentile) < 0.04)
      let z = fixture.percentile == 3 ? -1.8807936081512509 : fixture.percentile == 15 ? -1.0364333894937898
        : fixture.percentile == 85 ? 1.0364333894937898 : fixture.percentile == 97 ? 1.8807936081512509 : 0
      let cm = try #require(MeasurementForAge.whoCentimeters(zScore: z, metric: fixture.metric,
        ageDays: fixture.day, sex: fixture.sex))
      #expect(abs(cm - fixture.centimeters) < 0.0011)
    }
  }
  @Test func exactUnitsAndVersionedRecordsPreserveOriginalPositionDateAndNote() throws {
    #expect(LengthUnit.inch.toCentimeters(13.5) == Decimal(string: "34.29"))
    #expect(LengthUnit.inch.fromCentimeters(Decimal(string: "34.29")!) == 13.5)
    let profile = child()
    for payload: ActivityPayload in [.length(centimeters: 50.8, unit: .inch, position: .standing),
      .headCircumference(centimeters: 34.29, unit: .inch)] {
      let entry = Activity(familyID: profile.familyID, childID: profile.id,
        occurredAt: date("2026-09-03T09:00:00-04:00"), authorID: UUID(), note: "Clinic measurement", payload: payload)
      let envelope = RecordEnvelope(value: .activity(entry))
      #expect(envelope.version == 5)
      #expect(try JSONDecoder().decode(RecordEnvelope.self, from: JSONEncoder().encode(envelope)) == envelope)
    }
    let weight = Activity(familyID: profile.familyID, childID: profile.id, occurredAt: .now,
      authorID: UUID(), payload: .weight(grams: 4000, unit: "kg"))
    #expect(RecordEnvelope(value: .activity(weight)).version == 1)
  }
  @Test func positionAdjustmentUsesWHOAgeBoundaryWithoutRewritingEnteredValues() throws {
    let profile = child()
    let at = date("2026-09-01T12:00:00-04:00")
    let lying = try MeasurementForAge.evaluate(centimeters: 49.8842, metric: .length,
      child: profile, at: at, calendar: calendar, now: at)
    let standing = try MeasurementForAge.evaluate(centimeters: 49.1842, metric: .length, position: .standing,
      child: profile, at: at, calendar: calendar, now: at)
    #expect(abs(lying.percentile - 50) < 0.001)
    #expect(abs(lying.percentile - standing.percentile) < 0.001)
    #expect(standing.adjustmentCM == 0.7)
    #expect(abs(standing.referenceCentimeters - 49.8842) < 0.0001)
    #expect(MeasurementForAge.whoAdjustment(metric: .length, position: .standing, ageDays: 730) == 0.7)
    #expect(MeasurementForAge.whoAdjustment(metric: .length, position: .standing, ageDays: 731) == 0)
    #expect(MeasurementForAge.whoAdjustment(metric: .length, position: .lyingDown, ageDays: 731) == -0.7)
    #expect(MeasurementForAge.whoAdjustment(metric: .headCircumference, position: .standing, ageDays: 20) == 0)
  }
  @Test func usesWHOOnEventDateAndShowsBothAgeComparisons() throws {
    let profile = child(gestation: 35 * 7 + 4)
    let at = calendar.date(byAdding: .day, value: 36, to: profile.birthDate!)!
    let reading = try MeasurementForAge.evaluate(centimeters: 36, metric: .headCircumference,
      child: profile, at: at, calendar: calendar, now: at.addingTimeInterval(86400 * 200))
    #expect(reading.age.days == 5)
    #expect(reading.age.standard == .who)
    let comparison = try #require(try MeasurementForAge.compareAges(centimeters: 36, metric: .headCircumference,
      child: profile, at: at, calendar: calendar, now: at))
    #expect(comparison.actual.days == 36)
    #expect(comparison.corrected?.days == 5)
    #expect(comparison.actual.percentile != comparison.corrected?.percentile)
    let beforeDue = calendar.date(byAdding: .day, value: 10, to: profile.birthDate!)!
    #expect(try MeasurementForAge.compareAges(centimeters: 34, metric: .headCircumference,
      child: profile, at: beforeDue, calendar: calendar, now: beforeDue)?.corrected == nil)
    let transition = calendar.date(byAdding: .day, value: 64 * 7 - (35 * 7 + 4) + 1, to: profile.birthDate!)!
    let who = try MeasurementForAge.referenceAge(child: profile, at: transition, calendar: calendar, now: transition)
    #expect(who.standard == .who && who.isCorrected && who.days == 24 * 7 + 1)
    let standing = try MeasurementForAge.evaluate(centimeters: 50, metric: .length, position: .standing,
      child: profile, at: at, calendar: calendar, now: at)
    #expect(standing.age.standard == .who && standing.adjustmentCM == 0.7)
  }
  @Test func boundsFollowCalendarBirthdaysAndStopCorrectionAtTwo() throws {
    var profile = child(gestation: 35 * 7)
    profile.birthDate = date("2024-02-29T12:00:00-05:00")
    let second = calendar.date(byAdding: .year, value: 2, to: profile.birthDate!)!
    let before = calendar.date(byAdding: .day, value: -1, to: second)!
    #expect(try MeasurementForAge.referenceAge(child: profile, at: before, calendar: calendar, now: second).isCorrected)
    #expect(try !MeasurementForAge.referenceAge(child: profile, at: second, calendar: calendar, now: second).isCorrected)
    #expect(try MeasurementForAge.compareAges(centimeters: 47, metric: .headCircumference,
      child: profile, at: second, calendar: calendar, now: second) == nil)
    let fifth = calendar.date(byAdding: .year, value: 5, to: profile.birthDate!)!
    _ = try MeasurementForAge.evaluate(centimeters: 50, metric: .headCircumference,
      child: profile, at: fifth, calendar: calendar, now: fifth)
    let after = calendar.date(byAdding: .day, value: 1, to: fifth)!
    #expect(throws: MeasurementForAge.Unavailable.ageOutsideRange) {
      try MeasurementForAge.evaluate(centimeters: 50, metric: .headCircumference,
        child: profile, at: after, calendar: calendar, now: after)
    }
  }
  @Test func missingInvalidAndFutureDataNeverInventAPercentile() throws {
    let at = date("2026-09-20T12:00:00-04:00")
    func check(_ profile: ChildProfile, value: Double = 35, date: Date? = nil) throws -> MeasurementForAge.Reading {
      try MeasurementForAge.evaluate(centimeters: value, metric: .headCircumference,
        child: profile, at: date ?? at, calendar: calendar, now: at)
    }
    var profile = child(); profile.birthDate = nil
    #expect(throws: MeasurementForAge.Unavailable.missingBirthDate) { try check(profile) }
    #expect(throws: MeasurementForAge.Unavailable.missingReference) { try check(child(sex: nil)) }
    for value in [0, -1, Double.infinity, Double.nan] {
      #expect(throws: MeasurementForAge.Unavailable.invalidMeasurement) { try check(child(), value: value) }
    }
    #expect(throws: MeasurementForAge.Unavailable.futureMeasurement) { try check(child(), date: at.addingTimeInterval(1)) }
    #expect(throws: MeasurementForAge.Unavailable.beforeBirth) { try check(child(), date: date("2026-08-31T12:00:00-04:00")) }
    #expect(throws: MeasurementForAge.Unavailable.invalidGestation) { try check(child(gestation: 0)) }
    #expect(throws: MeasurementForAge.Unavailable.correctedAgeNotStarted) { try check(child(gestation: 25 * 7)) }
    #expect(throws: MeasurementForAge.Unavailable.correctedAgeNotStarted) {
      try check(child(gestation: 26 * 7), date: date("2026-09-01T12:00:00-04:00"))
    }
    #expect(MeasurementForAge.whoPercentile(centimeters: 35, metric: .headCircumference, ageDays: -1, sex: .male) == nil)
  }
  @Test func projectionKeepsSiblingsAndMetricsSeparateAndRetainsUnsupportedEntries() throws {
    let profile = child()
    let at = date("2026-09-20T12:00:00-04:00")
    func entry(_ payload: ActivityPayload, id: UUID? = nil, eventDate: Date? = nil) -> Activity {
      Activity(familyID: profile.familyID, childID: id ?? profile.id, occurredAt: eventDate ?? at,
        authorID: UUID(), payload: payload)
    }
    let a = entry(.headCircumference(centimeters: 35, unit: .cm))
    let b = entry(.headCircumference(centimeters: 35.5, unit: .inch))
    let unrelated = [entry(.length(centimeters: 51, unit: .cm, position: .lyingDown)),
      entry(.headCircumference(centimeters: 37, unit: .cm), id: UUID()),
      entry(.headCircumference(centimeters: 36, unit: .cm), eventDate: at.addingTimeInterval(-86400 * 40))]
    let interval = DateInterval(start: at.addingTimeInterval(-86400 * 7), end: at)
    let series = MeasurementGrowthSeries(entries: unrelated + [b, a], child: profile, metric: .headCircumference,
      interval: interval, calendar: calendar, now: at)
    #expect(Set(series.measurements.map(\.id)) == [a.id, b.id])
    #expect(series.measurements.allSatisfy { $0.reading != nil })
    #expect(series.curves.count == 3)
    var unknown = profile; unknown.birthDate = nil
    let withoutReference = MeasurementGrowthSeries(entries: [a], child: unknown, metric: .headCircumference,
      interval: interval, calendar: calendar, now: at)
    #expect(withoutReference.measurements.count == 1 && withoutReference.curves.isEmpty)
    #expect(withoutReference.measurements[0].unavailable != nil)
  }
  @Test func curvesUseOnlyWHOAndSplitAtLengthHeightTransitions() throws {
    let profile = child(gestation: 35 * 7)
    let day = calendar.date(byAdding: .day, value: 64 * 7 - 35 * 7, to: profile.birthDate!)!
    let activity = Activity(familyID: profile.familyID, childID: profile.id, occurredAt: day,
      authorID: UUID(), payload: .length(centimeters: 65, unit: .cm, position: .lyingDown))
    let end = calendar.date(byAdding: .day, value: 4, to: day)!
    let series = MeasurementGrowthSeries(entries: [activity], child: profile, metric: .length,
      interval: DateInterval(start: day.addingTimeInterval(-86400 * 4), end: end), calendar: calendar, now: end)
    #expect(series.standards == [.who] && series.curves.count == 3)
    #expect(series.curves.allSatisfy { Set($0.points.map { try? MeasurementForAge.referenceAge(child: profile, at: $0.date, calendar: calendar, now: end).standard }).count == 1 })
    var term = profile; term.gestationalAgeAtBirthDays = nil
    let two = calendar.date(byAdding: .day, value: 731, to: term.birthDate!)!
    let height = Activity(familyID: term.familyID, childID: term.id, occurredAt: two,
      authorID: UUID(), payload: .length(centimeters: 87, unit: .cm, position: .standing))
    let after = calendar.date(byAdding: .day, value: 4, to: two)!
    let heightSeries = MeasurementGrowthSeries(entries: [height], child: term, metric: .length,
      interval: DateInterval(start: two.addingTimeInterval(-86400 * 4), end: after), calendar: calendar, now: after)
    #expect(heightSeries.curves.count == 6)
  }
}
