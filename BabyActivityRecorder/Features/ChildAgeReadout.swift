import SwiftUI

struct ChildAgeReadout: View {
  let age: ChildAge
  let calendar: Calendar

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      LabeledContent("Age", value: age.chronologicalDuration)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Age, \(age.spokenChronologicalDuration)")
      if let gestation = age.currentGestationalDays {
        LabeledContent("Gestational age now", value: ChildAge.duration(gestation))
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("Gestational age now, \(ChildAge.spokenDuration(gestation))")
      }
      if let corrected = age.correctedLabel {
        LabeledContent("Corrected age", value: corrected)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(correctedAccessibilityLabel)
      }
      if let dueDate = age.estimatedDueDate {
        LabeledContent("Estimated due date") {
          Text(
            dueDate,
            format: Date.FormatStyle(
              date: .abbreviated, time: .omitted, calendar: calendar, timeZone: calendar.timeZone))
        }
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private var correctedAccessibilityLabel: String {
    guard let days = age.correctedDays else { return "" }
    if days < 0 { return String(localized: "Corrected age, due in \(ChildAge.spokenDuration(-days))") }
    if days == 0 { return String(localized: "Corrected age, due today") }
    return String(localized: "Corrected age, \(ChildAge.spokenDuration(days))")
  }
}
