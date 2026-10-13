import Foundation

/// Length/height and head circumference on the measurement date, using official offline data.
/// Source, measurement-position adjustment, bounds, and independent fixtures:
/// ReferenceData/GrowthMeasurements/README.md.
enum MeasurementForAge {
  struct LMS: Sendable {
    let l: Double
    let m: Double
    let s: Double
  }
  typealias ReferenceAge = WeightForAge.ReferenceAge
  typealias Standard = WeightForAge.Standard

  struct Reading: Equatable, Sendable {
    let percentile: Double
    let age: ReferenceAge
    let reference: GrowthReferenceSex
    /// The value used by the reference, without rewriting the recorded measurement.
    let referenceCentimeters: Double
    let adjustmentCM: Double
    var percentileLabel: String { WHOWeightForAge.label(for: percentile) }
    var referenceLabel: String { "\(age.standard.title) · \(reference.title)" }
    var context: String { "\(age.label) · \(referenceLabel)" }
  }

  struct WHOReading: Equatable, Sendable {
    let percentile: Double
    let days: Int
    var percentileLabel: String { WHOWeightForAge.label(for: percentile) }
  }
  struct AgeComparison: Equatable, Sendable {
    let reference: GrowthReferenceSex
    let actual: WHOReading
    let corrected: WHOReading?
    let correctedDays: Int
  }

  enum Unavailable: Error, Equatable, LocalizedError {
    case missingBirthDate, missingReference, invalidDate, beforeBirth, futureMeasurement
    case ageOutsideRange, invalidGestation, invalidMeasurement
    case correctedAgeNotStarted
    var errorDescription: String? {
      switch self {
      case .missingBirthDate: String(localized: "Add a birth date to compare measurements by age.")
      case .missingReference: String(localized: "Choose a Boys or Girls growth reference in the child’s profile.")
      case .invalidDate: String(localized: "Check the birth date and measurement date.")
      case .beforeBirth: String(localized: "This measurement is dated before the recorded birth date.")
      case .futureMeasurement: String(localized: "Percentiles are available for measurements up to today.")
      case .ageOutsideRange: String(localized: "These WHO comparisons cover birth through the fifth birthday. Measurements are still saved at other ages.")
      case .invalidGestation: String(localized: "Check gestational age at birth in the child’s profile.")
      case .invalidMeasurement: String(localized: "A percentile needs a recorded measurement greater than zero.")
      case .correctedAgeNotStarted: String(localized: "WHO corrected-age comparisons begin on the estimated due date. This measurement is still saved.")
      }
    }
  }

  private static func validatedAge(child: ChildProfile, at date: Date, calendar: Calendar, now: Date) throws -> ChildAge {
    guard let birth = child.birthDate else { throw Unavailable.missingBirthDate }
    guard birth.timeIntervalSinceReferenceDate.isFinite, date.timeIntervalSinceReferenceDate.isFinite,
      now.timeIntervalSinceReferenceDate.isFinite else { throw Unavailable.invalidDate }
    guard date <= now else { throw Unavailable.futureMeasurement }
    let birthDay = calendar.startOfDay(for: birth)
    let day = calendar.startOfDay(for: date)
    guard day >= birthDay else { throw Unavailable.beforeBirth }
    guard let fifthBirthday = calendar.date(byAdding: .year, value: 5, to: birthDay),
      day <= fifthBirthday,
      let age = ChildAge(child: child, at: date, calendar: calendar) else { throw Unavailable.ageOutsideRange }
    if let gestation = child.gestationalAgeAtBirthDays, !ChildAge.gestationalDaysRange.contains(gestation) {
      throw Unavailable.invalidGestation
    }
    return age
  }

  private static func beforeSecondBirthday(child: ChildProfile, at date: Date, calendar: Calendar) -> Bool {
    guard let birth = child.birthDate,
      let second = calendar.date(byAdding: .year, value: 2, to: calendar.startOfDay(for: birth)) else { return false }
    return calendar.startOfDay(for: date) < second
  }

  static func referenceAge(child: ChildProfile, at date: Date, calendar: Calendar, now: Date) throws -> ReferenceAge {
    let age = try validatedAge(child: child, at: date, calendar: calendar, now: now)
    let corrected = beforeSecondBirthday(child: child, at: date, calendar: calendar) ? age.correctedDays : nil
    if let corrected, corrected < 0 { throw Unavailable.correctedAgeNotStarted }
    return ReferenceAge(days: corrected ?? age.chronologicalDays, chronologicalDays: age.chronologicalDays,
      isCorrected: corrected != nil, standard: .who)
  }

  static func coefficients(metric: GrowthMeasurementMetric, ageDays: Int, sex: GrowthReferenceSex) -> LMS? {
    let data: [LMS]
    switch (metric, sex) {
    case (.length, .male): data = WHOMeasurementReference.lengthMale
    case (.length, .female): data = WHOMeasurementReference.lengthFemale
    case (.headCircumference, .male): data = WHOMeasurementReference.headCircumferenceMale
    case (.headCircumference, .female): data = WHOMeasurementReference.headCircumferenceFemale
    }
    guard data.indices.contains(ageDays) else { return nil }
    return data[ageDays]
  }

  /// WHO Anthro uses length through day 730, standing height from day 731.
  static func whoAdjustment(metric: GrowthMeasurementMetric, position: LengthMeasurementPosition, ageDays: Int) -> Double {
    guard metric == .length else { return 0 }
    return ageDays <= 730 ? (position == .standing ? 0.7 : 0) : (position == .lyingDown ? -0.7 : 0)
  }

  static func whoPercentile(centimeters: Double, metric: GrowthMeasurementMetric, ageDays: Int, sex: GrowthReferenceSex) -> Double? {
    guard centimeters.isFinite, centimeters > 0, let row = coefficients(metric: metric, ageDays: ageDays, sex: sex) else { return nil }
    let z = row.l == 0 ? log(centimeters / row.m) / row.s : (pow(centimeters / row.m, row.l) - 1) / (row.l * row.s)
    return 50 * erfc(-z / sqrt(2))
  }

  static func whoCentimeters(zScore: Double, metric: GrowthMeasurementMetric, ageDays: Int, sex: GrowthReferenceSex) -> Double? {
    guard zScore.isFinite, abs(zScore) <= 3, let row = coefficients(metric: metric, ageDays: ageDays, sex: sex) else { return nil }
    return row.l == 0 ? row.m * exp(row.s * zScore) : row.m * pow(1 + row.l * row.s * zScore, 1 / row.l)
  }

  static func evaluate(centimeters: Double, metric: GrowthMeasurementMetric, position: LengthMeasurementPosition = .lyingDown,
    child: ChildProfile, at date: Date, calendar: Calendar, now: Date) throws -> Reading {
    guard centimeters.isFinite, centimeters > 0 else { throw Unavailable.invalidMeasurement }
    let age = try referenceAge(child: child, at: date, calendar: calendar, now: now)
    guard let sex = child.effectiveGrowthReferenceSex else { throw Unavailable.missingReference }
    let adjustment = whoAdjustment(metric: metric, position: position, ageDays: age.days)
    let value = centimeters + adjustment
    guard let percentile = whoPercentile(centimeters: value, metric: metric, ageDays: age.days, sex: sex)
    else { throw Unavailable.ageOutsideRange }
    return Reading(percentile: percentile, age: age, reference: sex, referenceCentimeters: value, adjustmentCM: adjustment)
  }

  static func centimeters(zScore: Double, metric: GrowthMeasurementMetric, age: ReferenceAge, sex: GrowthReferenceSex) -> Double? {
    whoCentimeters(zScore: zScore, metric: metric, ageDays: age.days, sex: sex)
  }

  static func compareAges(centimeters: Double, metric: GrowthMeasurementMetric, position: LengthMeasurementPosition = .lyingDown,
    child: ChildProfile, at date: Date, calendar: Calendar, now: Date) throws -> AgeComparison? {
    guard centimeters.isFinite, centimeters > 0 else { throw Unavailable.invalidMeasurement }
    let age = try validatedAge(child: child, at: date, calendar: calendar, now: now)
    guard let correctedDays = age.correctedDays, beforeSecondBirthday(child: child, at: date, calendar: calendar) else { return nil }
    guard let sex = child.effectiveGrowthReferenceSex else { throw Unavailable.missingReference }
    func reading(_ days: Int) throws -> WHOReading {
      let value = centimeters + whoAdjustment(metric: metric, position: position, ageDays: days)
      guard let percentile = whoPercentile(centimeters: value, metric: metric, ageDays: days, sex: sex) else { throw Unavailable.ageOutsideRange }
      return WHOReading(percentile: percentile, days: days)
    }
    return try AgeComparison(reference: sex, actual: reading(age.chronologicalDays),
      corrected: correctedDays >= 0 ? reading(correctedDays) : nil, correctedDays: correctedDays)
  }
}
