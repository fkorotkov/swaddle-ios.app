import Foundation
import Testing

@testable import LittleLogCore

struct WHOAgeComparisonTests {
  private var calendar: Calendar { WHOWeightForAgeTests().calendar }
  private func child(gestation: Int? = 35 * 7 + 4, sex: GrowthReferenceSex? = .male) -> ChildProfile {
    WHOWeightForAgeTests().child(born: "2026-09-01T00:00:00-04:00", gestation: gestation, sex: sex)
  }
  private func date(_ day: Int, child: ChildProfile) -> Date {
    calendar.date(byAdding: .day, value: day, to: child.birthDate!)!
  }
  private func comparison(_ day: Int, child: ChildProfile, grams: Double = 4180) throws
    -> WHOWeightForAge.AgeComparison?
  {
    let event = date(day, child: child)
    return try WHOWeightForAge.compareAges(
      grams: grams, child: child, at: event, calendar: calendar, now: event)
  }

  @Test(arguments: [GrowthReferenceSex.male, .female])
  func usesIndependentPublishedWHOValuesForEachAgeBasis(_ sex: GrowthReferenceSex) throws {
    let profile = child(gestation: 36 * 7 + 5, sex: sex) // 23 days before the due date.
    let samples = whoWeightReferenceFixtures.filter {
      $0.sex == sex && $0.percentile == 50 && [7, 30].contains($0.day)
    }
    #expect(samples.count == 2)
    for sample in samples {
      let result = try #require(try comparison(30, child: profile, grams: sample.kilograms * 1000))
      let corrected = try #require(result.corrected)
      #expect(result.actual.age.days == 30)
      #expect(corrected.age.days == 7)
      #expect(result.correctedDays == 7)
      #expect(!result.actual.age.isCorrected)
      #expect(corrected.age.isCorrected)
      #expect(corrected.reference == sex && result.actual.reference == sex)
      #expect(corrected.age.chronologicalDays == result.actual.age.chronologicalDays)
      #expect(corrected.percentile > result.actual.percentile)
      let matched = sample.day == 7 ? corrected : result.actual
      #expect(abs(matched.percentile - 50) < 0.08)
    }
  }

  @Test func correctedWHOStartsOnDueDateAndMatchesTheChart() throws {
    let profile = child()
    let before = try #require(try comparison(30, child: profile))
    #expect(before.correctedDays == -1)
    #expect(before.corrected == nil)
    #expect(before.actual.age.days == 30)
    let due = try #require(try comparison(31, child: profile, grams: 3346.4))
    #expect(due.corrected?.age.days == 0)
    #expect(abs(try #require(due.corrected?.percentile) - 50) < 0.00001)
    let result = try #require(try comparison(36, child: profile))
    #expect(result.corrected?.age.days == 5)
    #expect(result.actual.age.days == 36)
    let event = date(36, child: profile)
    let primary = try WeightForAge.evaluate(
      grams: 4180, child: profile, at: event, calendar: calendar, now: event)
    #expect(primary.age.standard == .who)
    #expect(primary.age.days == 5)
    #expect(primary.percentileLabel == "92nd percentile")
    #expect(primary.percentile == result.corrected?.percentile)
    let who = try WHOWeightForAge.evaluate(grams: 4180, child: profile,
      at: event, calendar: calendar, now: event)
    #expect(who.percentile == primary.percentile)
  }

  @Test func correctedComparisonMatchesPrimaryWHOLaterInInfancy() throws {
    let profile = child()
    let event = date(200, child: profile)
    let result = try #require(try comparison(200, child: profile, grams: 7500))
    let primary = try WeightForAge.evaluate(
      grams: 7500, child: profile, at: event, calendar: calendar, now: event)
    #expect(primary.age.standard == .who)
    #expect(primary.percentile == result.corrected?.percentile)
    #expect(result.actual.percentile < primary.percentile)
  }

  @Test(arguments: [nil, 37 * 7, 40 * 7, 42 * 7])
  func termAndUnknownGestationDoNotShowDuplicateComparisons(_ gestation: Int?) throws {
    #expect(try comparison(36, child: child(gestation: gestation)) == nil)
  }

  @Test func validationDoesNotAllowMadeUpComparisons() throws {
    let profile = child()
    let event = date(36, child: profile)
    for grams in [0, -1, Double.nan, Double.infinity] {
      #expect(throws: WHOWeightForAge.Unavailable.invalidWeight) {
        try comparison(36, child: profile, grams: grams)
      }
    }
    #expect(throws: WHOWeightForAge.Unavailable.missingReference) {
      try comparison(36, child: child(sex: nil))
    }
    #expect(throws: WHOWeightForAge.Unavailable.invalidGestation) {
      try comparison(36, child: child(gestation: Int.max))
    }
    #expect(throws: WHOWeightForAge.Unavailable.beforeBirth) { try comparison(-1, child: profile) }
    #expect(throws: WHOWeightForAge.Unavailable.futureMeasurement) {
      try WHOWeightForAge.compareAges(
        grams: 4180, child: profile, at: event.addingTimeInterval(1), calendar: calendar, now: event)
    }
    var missing = profile
    missing.birthDate = nil
    #expect(throws: WHOWeightForAge.Unavailable.missingBirthDate) {
      try WHOWeightForAge.compareAges(
        grams: 4180, child: missing, at: event, calendar: calendar, now: event)
    }
    let birthday = calendar.date(byAdding: .year, value: 2, to: profile.birthDate!)!
    #expect(throws: WHOWeightForAge.Unavailable.ageOutsideRange) {
      try WHOWeightForAge.compareAges(
        grams: 12000, child: profile, at: birthday, calendar: calendar, now: birthday)
    }
  }

  @Test func historicalComparisonsUseFamilyCalendarAcrossDST() throws {
    let helpers = WHOWeightForAgeTests()
    let profile = helpers.child(born: "2026-03-07T00:00:00-05:00", gestation: 36 * 7 + 6)
    let beforeDue = helpers.date("2026-03-28T23:59:00-04:00")
    let due = helpers.date("2026-03-29T00:01:00-04:00")
    let now = helpers.date("2026-06-01T12:00:00-04:00")
    let first = try #require(try WHOWeightForAge.compareAges(
      grams: 3500, child: profile, at: beforeDue, calendar: calendar, now: now))
    let second = try #require(try WHOWeightForAge.compareAges(
      grams: 3500, child: profile, at: due, calendar: calendar, now: now))
    #expect(first.actual.age.days == 21 && first.correctedDays == -1)
    #expect(first.corrected == nil)
    #expect(second.actual.age.days == 22 && second.corrected?.age.days == 0)
  }

  @Test func eachChartMeasurementKeepsItsOwnComparisonsAndOriginalCurves() throws {
    let profile = child()
    let start = date(30, child: profile)
    let end = date(37, child: profile)
    func event(_ day: Int, childID: UUID, grams: Decimal) -> Activity {
      Activity(familyID: profile.familyID, childID: childID, occurredAt: date(day, child: profile),
        authorID: UUID(), payload: .weight(grams: grams, unit: "kg"))
    }
    let before = event(30, childID: profile.id, grams: 4000)
    let after = event(36, childID: profile.id, grams: 4180)
    let sibling = event(36, childID: UUID(), grams: 5000)
    let series = WeightGrowthSeries(entries: [after, sibling, before], child: profile,
      interval: .init(start: start, end: end), calendar: calendar, now: end)
    #expect(series.measurements.map(\.id) == [before.id, after.id])
    #expect(series.measurements.map { $0.whoAgeComparison?.actual.age.days } == [30, 36])
    #expect(series.measurements.map { $0.whoAgeComparison?.corrected?.age.days } == [nil, 5])
    #expect(series.measurements.map(\.kilograms) == [4, 4.18])
    #expect(series.standards == [.who])
    #expect(series.curves.count == 3)
    #expect(series.measurements[0].reading == nil && series.measurements[1].reading?.age.standard == .who)
  }
}
