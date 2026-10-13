import Foundation

/// Calendar-day ages use the family's reporting zone, including across DST changes.
struct ChildAge: Equatable, Sendable {
  static let gestationalWeeksRange = 1...45
  static let gestationalDaysRange = 7...(45 * 7 + 6)
  static let dueDateGestationDays = 40 * 7

  let chronologicalDays: Int
  private let chronologicalMonths: Int
  private let daysAfterMonths: Int
  let gestationalDaysAtBirth: Int?
  let currentGestationalDays: Int?
  let estimatedDueDate: Date?
  let correctedDays: Int?

  init?(child: ChildProfile, at now: Date, calendar: Calendar) {
    guard let birth = child.birthDate,
      birth.timeIntervalSinceReferenceDate.isFinite,
      now.timeIntervalSinceReferenceDate.isFinite
    else { return nil }
    let birthDay = calendar.startOfDay(for: birth)
    let today = calendar.startOfDay(for: now)
    guard birthDay <= today,
      let days = calendar.dateComponents([.day], from: birthDay, to: today).day
    else { return nil }
    chronologicalDays = days
    // Use whole calendar months and remaining days, rather than dividing by 30.
    let calendarAge = calendar.dateComponents([.month, .day], from: birthDay, to: today)
    chronologicalMonths = calendarAge.month ?? 0
    daysAfterMonths = calendarAge.day ?? days

    guard let gestation = child.gestationalAgeAtBirthDays,
      Self.gestationalDaysRange.contains(gestation)
    else {
      gestationalDaysAtBirth = nil
      currentGestationalDays = nil
      estimatedDueDate = nil
      correctedDays = nil
      return
    }
    gestationalDaysAtBirth = gestation
    currentGestationalDays = gestation + days
    estimatedDueDate = calendar.date(
      byAdding: .day, value: Self.dueDateGestationDays - gestation, to: birthDay)
    // Corrected age applies to babies born before 37 completed weeks. Keep
    // negative days until the due date so the UI can say "Due in" honestly.
    correctedDays = gestation < 37 * 7 ? days - (Self.dueDateGestationDays - gestation) : nil
  }

  var chronologicalLabel: String {
    chronologicalDays == 0 ? String(localized: "Born today") : String(localized: "\(chronologicalDuration) old")
  }

  var chronologicalDuration: String {
    guard chronologicalMonths > 0 else { return Self.duration(chronologicalDays) }
    let months = String(localized: "\(chronologicalMonths)mo")
    return daysAfterMonths == 0 ? months : String(localized: "\(months) \(daysAfterMonths)d")
  }

  var spokenChronologicalDuration: String {
    guard chronologicalMonths > 0 else { return Self.spokenDuration(chronologicalDays) }
    let months = chronologicalMonths == 1 ? String(localized: "1 month") : String(localized: "\(chronologicalMonths) months")
    let days = daysAfterMonths == 1 ? String(localized: "1 day") : String(localized: "\(daysAfterMonths) days")
    return daysAfterMonths == 0 ? months : ListFormatter.localizedString(byJoining: [months, days])
  }

  var correctedLabel: String? {
    guard let correctedDays else { return nil }
    if correctedDays < 0 { return String(localized: "Due in \(Self.duration(-correctedDays))") }
    if correctedDays == 0 { return String(localized: "Due today") }
    return Self.duration(correctedDays)
  }

  static func duration(_ days: Int) -> String {
    let weeks = days / 7
    let remainder = days % 7
    if weeks == 0 { return String(localized: "\(remainder)d") }
    return remainder == 0 ? String(localized: "\(weeks)w") : String(localized: "\(weeks)w \(remainder)d")
  }

  static func spokenDuration(_ days: Int) -> String {
    let weeks = days / 7
    let remainder = days % 7
    let weekText = weeks == 1 ? String(localized: "1 week") : String(localized: "\(weeks) weeks")
    let dayText = remainder == 1 ? String(localized: "1 day") : String(localized: "\(remainder) days")
    if weeks == 0 { return dayText }
    return remainder == 0 ? weekText : ListFormatter.localizedString(byJoining: [weekText, dayText])
  }
}

extension ChildProfile {
  func validateBirthDetails(now: Date) throws {
    if let birthDate {
      guard birthDate.timeIntervalSinceReferenceDate.isFinite, birthDate <= now else {
        throw LogError.message(String(localized: "A birth date can’t be in the future."))
      }
    }
    if let gestationalAgeAtBirthDays {
      guard birthDate != nil else {
        throw LogError.message(String(localized: "Include a birth date to calculate gestational age."))
      }
      guard ChildAge.gestationalDaysRange.contains(gestationalAgeAtBirthDays) else {
        throw LogError.message(String(localized: "Enter gestational age at birth as 1–45 weeks and 0–6 days."))
      }
    }
  }
}
