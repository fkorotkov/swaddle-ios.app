import Foundation

enum WeightUnit: String, Codable, CaseIterable, Identifiable, Sendable {
  case kg, lb
  static let preferenceKey = "growthWeightUnit"
  var id: Self { self }
  var label: String { self == .kg ? String(localized: "kg") : String(localized: "lb + oz") }
  var accessibilityLabel: String { self == .kg ? String(localized: "Kilograms") : String(localized: "Pounds and ounces") }
  func fromKilograms(_ value: Double) -> Double {
    self == .kg ? value : value / 0.45359237
  }
  func quantity(_ kilograms: Double) -> String {
    if self == .kg {
      return "\(kilograms.formatted(.number.precision(.fractionLength(0...3)))) kg"
    }
    return poundsAndOunces(fromKilograms(kilograms))
  }
  func axisLabel(_ value: Double) -> String {
    self == .kg
      ? value.formatted(.number.precision(.fractionLength(0...3)))
      : poundsAndOunces(value, omitZeroOunces: true)
  }
  private func poundsAndOunces(_ pounds: Double, omitZeroOunces: Bool = false) -> String {
    // Round before splitting so 16 rounded ounces carries into the next pound.
    let hundredthsOfOunces = (pounds * 16 * 100).rounded()
    let wholePounds = floor(hundredthsOfOunces / 1600)
    let ounces = hundredthsOfOunces.truncatingRemainder(dividingBy: 1600) / 100
    let poundLabel = "\(wholePounds.formatted(.number.precision(.fractionLength(0)))) lb"
    if omitZeroOunces && ounces == 0 { return poundLabel }
    return "\(poundLabel) \(ounces.formatted(.number.precision(.fractionLength(0...2)))) oz"
  }
}

enum LengthUnit: String, Codable, CaseIterable, Identifiable, Sendable {
  case cm
  case inch = "in"
  static let preferenceKey = "growthMeasurementUnit"
  var id: Self { self }
  var label: String { rawValue }
  func toCentimeters(_ value: Decimal) -> Decimal {
    self == .cm ? value : value * Decimal(string: "2.54")!
  }
  func fromCentimeters(_ value: Decimal) -> Decimal {
    self == .cm ? value : value / Decimal(string: "2.54")!
  }
  func quantity(_ centimeters: Decimal) -> String {
    "\(fromCentimeters(centimeters).formatted(.number.precision(.fractionLength(0...2)))) \(label)"
  }
}

enum LengthMeasurementPosition: String, Codable, CaseIterable, Identifiable, Sendable {
  case lyingDown, standing
  var id: Self { self }
  var title: String { self == .lyingDown ? String(localized: "Lying down") : String(localized: "Standing") }
  var measurementTitle: String { self == .lyingDown ? String(localized: "Length") : String(localized: "Height") }
}

enum GrowthMeasurementMetric: String, CaseIterable, Identifiable, Sendable {
  case length, headCircumference
  var id: Self { self }
  var kind: ActivityKind { self == .length ? .length : .headCircumference }
  var title: String { self == .length ? String(localized: "Length / height") : String(localized: "Head circumference") }
  var comparisonName: String { self == .length ? String(localized: "length / height") : String(localized: "head circumference") }
  var referenceURL: URL {
    URL(string: "https://www.who.int/tools/child-growth-standards/standards/\(self == .length ? "length-height-for-age" : "head-circumference-for-age")")!
  }
}
