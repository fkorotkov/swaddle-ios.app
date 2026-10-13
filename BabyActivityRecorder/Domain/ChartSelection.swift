import Foundation

enum ChartSelection {
  /// Match the whole calendar bucket, not the closest midnight, including DST days.
  static func day(containing date: Date?, among days: [Date], calendar: Calendar) -> Date? {
    guard let date else { return nil }
    let start = calendar.startOfDay(for: date)
    return days.first { $0 == start }
  }

  static func measurement(near date: Date?, among dates: [Date]) -> Date? {
    guard let date else { return nil }
    return dates.min {
      let left = abs($0.timeIntervalSince(date))
      let right = abs($1.timeIntervalSince(date))
      return left == right ? $0 < $1 : left < right
    }
  }
}

extension VolumeUnit {
  /// Keep hundredths from imported volumes visible when inspecting a chart.
  func chartQuantity(_ ml: Decimal) -> String {
    "\(fromML(ml).formatted(.number.precision(.fractionLength(0...2)))) \(label)"
  }
}
