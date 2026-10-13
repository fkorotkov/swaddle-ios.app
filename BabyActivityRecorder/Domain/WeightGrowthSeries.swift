import Foundation

/// A bounded, deterministic projection shared by the chart and its accessible list.
struct WeightGrowthSeries {
  struct Measurement: Identifiable {
    let activity: Activity
    let kilograms: Double
    let reading: WeightForAge.Reading?
    let whoAgeComparison: WHOWeightForAge.AgeComparison?
    let unavailable: String?
    var id: UUID { activity.id }
    var date: Date { activity.occurredAt }
  }

  struct Curve: Identifiable {
    let label: String
    let standard: WeightForAge.Standard
    let points: [Point]
    var id: String { "\(standard.rawValue)-\(label)" }
  }

  struct Point: Identifiable {
    let date: Date
    let kilograms: Double
    var id: Date { date }
  }

  let measurements: [Measurement]
  let curves: [Curve]

  var standards: [WeightForAge.Standard] {
    WeightForAge.Standard.allCases.filter { standard in curves.contains { $0.standard == standard } }
  }

  init(
    entries: [Activity], child: ChildProfile, interval: DateInterval, calendar: Calendar, now: Date
  ) {
    measurements = entries.compactMap { event in
      guard event.childID == child.id, case .weight(let grams, _) = event.payload,
        event.occurredAt >= interval.start, event.occurredAt <= interval.end,
        grams.double.isFinite, grams > 0
      else { return nil }
      let comparison = try? WHOWeightForAge.compareAges(
        grams: grams.double, child: child, at: event.occurredAt, calendar: calendar, now: now)
      do {
        let reading = try WeightForAge.evaluate(
          grams: grams.double, child: child, at: event.occurredAt, calendar: calendar, now: now)
        return Measurement(
          activity: event, kilograms: grams.double / 1000, reading: reading,
          whoAgeComparison: comparison, unavailable: nil)
      } catch {
        return Measurement(
          activity: event, kilograms: grams.double / 1000, reading: nil,
          whoAgeComparison: comparison, unavailable: error.localizedDescription)
      }
    }.sorted {
      $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
    }

    guard let sex = child.effectiveGrowthReferenceSex, !measurements.isEmpty else {
      curves = []
      return
    }
    var days: [(date: Date, age: WeightForAge.ReferenceAge)] = []
    var day = calendar.startOfDay(for: interval.start)
    // Trends permits at most 366 days. Bound this projection even with a malformed interval.
    for _ in 0..<367 {
      guard day <= min(interval.end, now) else { break }
      if let age = try? WeightForAge.referenceAge(
        child: child, at: day, calendar: calendar, now: now)
      {
        days.append((day, age))
      }
      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
    }
    // Extend through the final measurement time, rather than ending at midnight.
    if let last = days.last, last.date < interval.end,
      let age = try? WeightForAge.referenceAge(
        child: child, at: interval.end, calendar: calendar, now: now)
    {
      days.append((interval.end, age))
    }
    // Never draw a continuous percentile curve between two different references.
    curves = WeightForAge.Standard.allCases.flatMap { standard in
      [("3rd", -1.8807936081512509), ("50th", 0.0), ("97th", 1.8807936081512509)].compactMap { label, z in
        let points = days.compactMap { day -> Point? in
          guard day.age.standard == standard,
            let kg = WeightForAge.kilograms(zScore: z, age: day.age, sex: sex)
          else { return nil }
          return Point(date: day.date, kilograms: kg)
        }
        return points.isEmpty ? nil : Curve(label: label, standard: standard, points: points)
      }
    }
  }
}
