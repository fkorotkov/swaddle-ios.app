import Foundation

/// Chooses a reference on the measurement date without modifying stored care data.
enum WeightForAge {
  enum Standard: String, CaseIterable, Sendable {
    case who

    var title: String {
      String(localized: "WHO")
    }
  }

  struct ReferenceAge: Equatable, Sendable {
    let days: Int
    let chronologicalDays: Int
    let isCorrected: Bool
    let standard: Standard

    var label: String {
      let name = isCorrected ? String(localized: "Corrected age") : String(localized: "Age")
      return String(localized: "\(name) \(ChildAge.duration(days))")
    }
  }

  struct Reading: Equatable, Sendable {
    let percentile: Double
    let age: ReferenceAge
    let reference: GrowthReferenceSex

    var percentileLabel: String { WHOWeightForAge.label(for: percentile) }
    var referenceLabel: String { "\(age.standard.title) · \(reference.title)" }
    var context: String { "\(age.label) · \(referenceLabel)" }
  }

  static func referenceAge(
    child: ChildProfile, at date: Date, calendar: Calendar, now: Date
  ) throws -> ReferenceAge {
    let who = try WHOWeightForAge.referenceAge(child: child, at: date, calendar: calendar, now: now)
    return ReferenceAge(days: who.days, chronologicalDays: who.chronologicalDays,
      isCorrected: who.isCorrected, standard: .who)
  }

  static func evaluate(
    grams: Double, child: ChildProfile, at date: Date, calendar: Calendar, now: Date
  ) throws -> Reading {
    guard grams.isFinite, grams > 0 else { throw WHOWeightForAge.Unavailable.invalidWeight }
    let age = try referenceAge(child: child, at: date, calendar: calendar, now: now)
    guard let sex = child.effectiveGrowthReferenceSex else { throw WHOWeightForAge.Unavailable.missingReference }
    guard let percentile = WHOWeightForAge.percentile(kilograms: grams / 1000, ageDays: age.days, sex: sex)
    else { throw WHOWeightForAge.Unavailable.ageOutsideRange }
    return Reading(percentile: percentile, age: age, reference: sex)
  }

  static func kilograms(zScore: Double, age: ReferenceAge, sex: GrowthReferenceSex) -> Double? {
    WHOWeightForAge.kilograms(zScore: zScore, ageDays: age.days, sex: sex)
  }
}
