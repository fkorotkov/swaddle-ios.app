import Foundation
import Testing

@testable import LittleLogCore

struct ChartSelectionTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }
  private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

  @Test func afternoonSelectionStaysOnTheTappedDay() {
    let days = [date("2026-10-02T00:00:00-04:00"), date("2026-10-03T00:00:00-04:00")]
    for hour in [0, 12, 18, 23] {
      let tap = calendar.date(byAdding: .hour, value: hour, to: days[0])!
      #expect(ChartSelection.day(containing: tap, among: days, calendar: calendar) == days[0])
    }
    #expect(ChartSelection.day(containing: days[1], among: days, calendar: calendar) == days[1])
  }

  @Test(arguments: [
    ("2026-03-08T00:00:00-05:00", "2026-03-08T23:59:59-04:00"),
    ("2026-11-01T00:00:00-04:00", "2026-11-01T23:59:59-05:00"),
  ])
  func selectionUsesFamilyCalendarAcrossDaylightSavingChanges(start: String, end: String) {
    #expect(
      ChartSelection.day(containing: date(end), among: [date(start)], calendar: calendar)
        == date(start))
  }

  @Test func missingSelectionNeverInventsANeighboringDay() {
    let days = [date("2026-10-02T00:00:00-04:00")]
    #expect(ChartSelection.day(containing: nil, among: days, calendar: calendar) == nil)
    #expect(
      ChartSelection.day(
        containing: date("2026-10-03T00:00:00-04:00"), among: days, calendar: calendar) == nil)
    #expect(ChartSelection.day(containing: days[0], among: [], calendar: calendar) == nil)
  }

  @Test func weightSelectionUsesAnActualMeasurementWithStableTies() {
    let early = date("2026-10-02T09:00:00-04:00")
    let late = date("2026-10-02T17:00:00-04:00")
    #expect(
      ChartSelection.measurement(near: date("2026-10-02T16:00:00-04:00"), among: [early, late])
        == late)
    #expect(
      ChartSelection.measurement(near: date("2026-10-02T13:00:00-04:00"), among: [late, early])
        == early)
    #expect(ChartSelection.measurement(near: nil, among: [early, late]) == nil)
    #expect(ChartSelection.measurement(near: early, among: []) == nil)
  }

  @Test func inspectedVolumesKeepImportedHundredthsAndExistingOunceConvention() {
    #expect(VolumeUnit.ml.chartQuantity(Decimal(string: "73.93")!) == "73.93 mL")
    #expect(VolumeUnit.oz.chartQuantity(270) == "9 oz")
    #expect(VolumeUnit.oz.chartQuantity(Decimal(string: "73.93")!) == "2.46 oz")
  }
}
