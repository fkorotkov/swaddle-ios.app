import Foundation

/// Offline WHO weight-for-age, evaluated on the measurement's calendar date.
/// Scope and sources: ReferenceData/WHO/README.md. Never a nutritional diagnosis.
enum WHOWeightForAge {
  struct LMS: Sendable {
    let l: Double
    let m: Double
    let s: Double
  }

  struct ReferenceAge: Equatable, Sendable {
    let days: Int
    let chronologicalDays: Int
    let isCorrected: Bool

    var label: String {
      String(localized: "\(isCorrected ? String(localized: "Corrected age") : String(localized: "Age")) \(ChildAge.duration(days))")
    }
  }

  struct Reading: Equatable, Sendable {
    let percentile: Double
    let age: ReferenceAge
    let reference: GrowthReferenceSex

    var percentileLabel: String { WHOWeightForAge.label(for: percentile) }
    var context: String { String(localized: "\(age.label) · WHO \(reference.title.lowercased())") }
  }

  /// WHO comparisons for a preterm child, using both age bases for the same measurement.
  struct AgeComparison: Equatable, Sendable {
    let actual: Reading
    let corrected: Reading?
    // Keep negative days: a measurement before the due date has no WHO corrected-age row.
    let correctedDays: Int
  }

  enum Unavailable: Error, Equatable, LocalizedError {
    case missingBirthDate, missingReference, invalidDate, beforeBirth, futureMeasurement
    case ageOutsideRange, correctedAgeNotStarted, invalidGestation, invalidWeight

    var errorDescription: String? {
      switch self {
      case .missingBirthDate: String(localized: "Add a birth date to compare weight by age.")
      case .missingReference: String(localized: "Choose a Boys or Girls growth reference in the child’s profile.")
      case .invalidDate: String(localized: "Check the birth date and measurement date.")
      case .beforeBirth: String(localized: "This measurement is dated before the recorded birth date.")
      case .futureMeasurement: String(localized: "Percentiles are available for measurements up to today.")
      case .ageOutsideRange: String(localized: "WHO comparisons here cover birth to the second birthday.")
      case .correctedAgeNotStarted:
        String(localized: "WHO corrected-age comparisons begin on the estimated due date. This measurement is still saved.")
      case .invalidGestation: String(localized: "Check gestational age at birth in the child’s profile.")
      case .invalidWeight: String(localized: "A percentile needs a recorded weight greater than zero.")
      }
    }
  }

  static func referenceAge(
    child: ChildProfile, at date: Date, calendar: Calendar, now: Date
  ) throws -> ReferenceAge {
    let age = try validatedAge(child: child, at: date, calendar: calendar, now: now)
    if let corrected = age.correctedDays {
      guard corrected >= 0 else { throw Unavailable.correctedAgeNotStarted }
      return ReferenceAge(
        days: corrected, chronologicalDays: age.chronologicalDays, isCorrected: true)
    }
    return ReferenceAge(
      days: age.chronologicalDays, chronologicalDays: age.chronologicalDays, isCorrected: false)
  }

  /// Shared date validation; the caller separately enforces its reference's age range.
  static func validatedAge(
    child: ChildProfile, at date: Date, calendar: Calendar, now: Date
  ) throws -> ChildAge {
    guard let birth = child.birthDate else { throw Unavailable.missingBirthDate }
    guard birth.timeIntervalSinceReferenceDate.isFinite,
      date.timeIntervalSinceReferenceDate.isFinite, now.timeIntervalSinceReferenceDate.isFinite
    else { throw Unavailable.invalidDate }
    guard date <= now else { throw Unavailable.futureMeasurement }
    let birthDay = calendar.startOfDay(for: birth)
    let day = calendar.startOfDay(for: date)
    guard day >= birthDay else { throw Unavailable.beforeBirth }
    guard let secondBirthday = calendar.date(byAdding: .year, value: 2, to: birthDay),
      day < secondBirthday,
      let age = ChildAge(child: child, at: date, calendar: calendar)
    else { throw Unavailable.ageOutsideRange }
    if let gestation = child.gestationalAgeAtBirthDays,
      !ChildAge.gestationalDaysRange.contains(gestation)
    {
      throw Unavailable.invalidGestation
    }
    return age
  }

  static func evaluate(
    grams: Double, child: ChildProfile, at date: Date, calendar: Calendar, now: Date
  ) throws -> Reading {
    guard grams.isFinite, grams > 0 else { throw Unavailable.invalidWeight }
    let age = try referenceAge(child: child, at: date, calendar: calendar, now: now)
    guard let sex = child.effectiveGrowthReferenceSex else { throw Unavailable.missingReference }
    guard let percentile = percentile(kilograms: grams / 1000, ageDays: age.days, sex: sex) else {
      throw Unavailable.ageOutsideRange
    }
    return Reading(percentile: percentile, age: age, reference: sex)
  }

  /// Compare the same measurement on WHO using both age bases. The chart uses corrected
  /// age for a known preterm birth; the actual-age comparison remains separately labeled.
  static func compareAges(
    grams: Double, child: ChildProfile, at date: Date, calendar: Calendar, now: Date
  ) throws -> AgeComparison? {
    guard grams.isFinite, grams > 0 else { throw Unavailable.invalidWeight }
    let age = try validatedAge(child: child, at: date, calendar: calendar, now: now)
    guard let correctedDays = age.correctedDays else { return nil }
    guard let sex = child.effectiveGrowthReferenceSex else { throw Unavailable.missingReference }

    func reading(days: Int, isCorrected: Bool) throws -> Reading {
      guard let percentile = percentile(kilograms: grams / 1000, ageDays: days, sex: sex) else {
        throw Unavailable.ageOutsideRange
      }
      return Reading(
        percentile: percentile,
        age: ReferenceAge(
          days: days, chronologicalDays: age.chronologicalDays, isCorrected: isCorrected),
        reference: sex)
    }

    return try AgeComparison(
      actual: reading(days: age.chronologicalDays, isCorrected: false),
      corrected: correctedDays >= 0 ? reading(days: correctedDays, isCorrected: true) : nil,
      correctedDays: correctedDays)
  }

  static func coefficients(ageDays: Int, sex: GrowthReferenceSex) -> LMS? {
    let data = sex == .male ? WHOWeightReference.male : WHOWeightReference.female
    guard data.indices.contains(ageDays) else { return nil }
    return data[ageDays]
  }

  static func percentile(kilograms: Double, ageDays: Int, sex: GrowthReferenceSex) -> Double? {
    guard kilograms.isFinite, kilograms > 0,
      let row = coefficients(ageDays: ageDays, sex: sex)
    else { return nil }
    let z =
      row.l == 0
      ? log(kilograms / row.m) / row.s
      : (pow(kilograms / row.m, row.l) - 1) / (row.l * row.s)
    // We present the tails only as below 1st / above 99th, not extreme z-scores.
    return 50 * erfc(-z / sqrt(2))
  }

  /// Inverse LMS for the reference curves. No interpolation of monthly tables.
  static func kilograms(zScore: Double, ageDays: Int, sex: GrowthReferenceSex) -> Double? {
    guard zScore.isFinite, abs(zScore) <= 3,
      let row = coefficients(ageDays: ageDays, sex: sex)
    else { return nil }
    return row.l == 0
      ? row.m * exp(row.s * zScore)
      : row.m * pow(1 + row.l * row.s * zScore, 1 / row.l)
  }

  static func label(for percentile: Double) -> String {
    String(localized: "\(rankLabel(for: percentile)) percentile")
  }

  static func rankLabel(for percentile: Double) -> String {
    if percentile < 1 { return String(localized: "Below 1st") }
    if percentile > 99 { return String(localized: "Above 99th") }
    let formatter = NumberFormatter()
    formatter.numberStyle = .ordinal
    let rounded = min(99, max(1, Int(percentile.rounded())))
    let ordinal = formatter.string(from: NSNumber(value: rounded)) ?? "\(rounded)"
    return ordinal
  }
}
