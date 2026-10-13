import Foundation

/// One projection supplies the plot, selected detail, and accessible measurement list.
struct MeasurementGrowthSeries {
  struct Measurement: Identifiable {
    let activity: Activity
    let centimeters: Double
    let position: LengthMeasurementPosition
    let reading: MeasurementForAge.Reading?
    let whoAgeComparison: MeasurementForAge.AgeComparison?
    let unavailable: String?
    var id: UUID { activity.id }
    var date: Date { activity.occurredAt }
    var chartedCentimeters: Double { reading?.referenceCentimeters ?? centimeters }
  }
  struct Point: Identifiable {
    let date: Date
    let centimeters: Double
    var id: Date { date }
  }
  struct Curve: Identifiable {
    let id: String
    let label: String
    let standard: MeasurementForAge.Standard
    let points: [Point]
  }
  let measurements: [Measurement]
  let curves: [Curve]
  var standards: [MeasurementForAge.Standard] {
    MeasurementForAge.Standard.allCases.filter { standard in curves.contains { $0.standard == standard } }
  }
  init(entries: [Activity], child: ChildProfile, metric: GrowthMeasurementMetric,
    interval: DateInterval, calendar: Calendar, now: Date) {
    measurements = entries.compactMap { event in
      guard event.childID == child.id, event.occurredAt >= interval.start, event.occurredAt <= interval.end else { return nil }
      let centimeters: Double
      let position: LengthMeasurementPosition
      switch (metric, event.payload) {
      case (.length, .length(let value, _, let method)): centimeters = value.double; position = method
      case (.headCircumference, .headCircumference(let value, _)): centimeters = value.double; position = .lyingDown
      default: return nil
      }
      guard centimeters.isFinite, centimeters > 0 else { return nil }
      let comparison = try? MeasurementForAge.compareAges(centimeters: centimeters, metric: metric, position: position,
        child: child, at: event.occurredAt, calendar: calendar, now: now)
      do {
        let reading = try MeasurementForAge.evaluate(centimeters: centimeters, metric: metric, position: position,
          child: child, at: event.occurredAt, calendar: calendar, now: now)
        return Measurement(activity: event, centimeters: centimeters, position: position,
          reading: reading, whoAgeComparison: comparison, unavailable: nil)
      } catch {
        return Measurement(activity: event, centimeters: centimeters, position: position,
          reading: nil, whoAgeComparison: comparison, unavailable: error.localizedDescription)
      }
    }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
    guard let sex = child.effectiveGrowthReferenceSex, measurements.contains(where: { $0.reading != nil }) else {
      curves = []; return
    }
    var days: [(date: Date, age: MeasurementForAge.ReferenceAge)] = []
    var day = calendar.startOfDay(for: interval.start)
    for _ in 0..<367 {
      guard day <= min(interval.end, now) else { break }
      if let age = try? MeasurementForAge.referenceAge(child: child, at: day, calendar: calendar, now: now) {
        days.append((day, age))
      }
      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
    }
    if let last = days.last, last.date < interval.end,
      let age = try? MeasurementForAge.referenceAge(child: child, at: interval.end, calendar: calendar, now: now) {
      days.append((interval.end, age))
    }
    func basis(_ age: MeasurementForAge.ReferenceAge) -> String {
      let method = metric == .length && age.standard == .who ? (age.days <= 730 ? "length" : "height") : metric.rawValue
      return "\(age.standard.rawValue)-\(age.isCorrected)-\(method)"
    }
    // Separate curve IDs across standard, age-basis, and WHO length/height transitions.
    let bases = Set(days.map { basis($0.age) }).sorted()
    curves = bases.flatMap { key in
      [("3rd", -1.8807936081512509), ("50th", 0.0), ("97th", 1.8807936081512509)].compactMap { label, z in
        let matching = days.filter { basis($0.age) == key }
        let points = matching.compactMap { day -> Point? in
          guard let value = MeasurementForAge.centimeters(zScore: z, metric: metric, age: day.age, sex: sex) else { return nil }
          return Point(date: day.date, centimeters: value)
        }
        guard let age = matching.first?.age, !points.isEmpty else { return nil }
        return Curve(id: "\(key)-\(label)", label: label, standard: age.standard, points: points)
      }
    }
  }
}
