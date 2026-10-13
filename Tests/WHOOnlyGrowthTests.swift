import Foundation
import Testing
@testable import LittleLogCore

struct WHOOnlyGrowthTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }
  private let birth = ISO8601DateFormatter().date(from: "2026-01-01T12:00:00-05:00")!

  @Test func everySupportedPretermGestationUsesWHOFromTheDueDate() throws {
    for gestation in stride(from: ChildAge.gestationalDaysRange.lowerBound, to: 37 * 7, by: 1) {
      let child = ChildProfile(familyID: UUID(), name: "Robin", birthDate: birth,
        gestationalAgeAtBirthDays: gestation, growthReferenceSex: .male)
      let due = try #require(calendar.date(byAdding: .day, value: 40 * 7 - gestation, to: birth))
      for days in [0, 1, 5, 70, 168] {
        let event = try #require(calendar.date(byAdding: .day, value: days, to: due))
        let median = try #require(WHOWeightForAge.coefficients(ageDays: days, sex: .male)).m
        let weight = try WeightForAge.evaluate(grams: median * 1000, child: child,
          at: event, calendar: calendar, now: event)
        #expect(weight.age.standard == .who && weight.age.days == days && weight.age.isCorrected)
        #expect(abs(weight.percentile - 50) < 0.000001)
        for metric in GrowthMeasurementMetric.allCases {
          let median = try #require(MeasurementForAge.coefficients(metric: metric, ageDays: days, sex: .male)).m
          let measurement = try MeasurementForAge.evaluate(centimeters: median, metric: metric,
            child: child, at: event, calendar: calendar, now: event)
          #expect(measurement.age.standard == .who && measurement.age.days == days)
          #expect(abs(measurement.percentile - 50) < 0.000001)
        }
      }
      let before = try #require(calendar.date(byAdding: .day, value: -1, to: due))
      #expect(throws: WHOWeightForAge.Unavailable.correctedAgeNotStarted) {
        try WeightForAge.evaluate(grams: 3500, child: child, at: before, calendar: calendar, now: due)
      }
      let comparison = try #require(try WHOWeightForAge.compareAges(grams: 3500, child: child,
        at: before, calendar: calendar, now: due))
      #expect(comparison.corrected == nil && comparison.actual.percentile.isFinite)
    }
  }
}
