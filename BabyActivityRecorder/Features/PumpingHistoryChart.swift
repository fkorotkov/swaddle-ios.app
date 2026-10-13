import Charts
import SwiftUI

struct PumpingHistoryChart: View {
  let entries: [PumpSession]
  let unit: VolumeUnit
  let calendar: Calendar
  @State private var selectedDate: Date?

  private var days: [DailyPumpingSummary] {
    Dictionary(grouping: entries) { calendar.startOfDay(for: $0.occurredAt) }
      .map { date, sessions in
        DailyPumpingSummary(
          date: date, totalML: sessions.reduce(0) { $0 + $1.totalML }, sessions: sessions.count)
      }
      .sorted { $0.date < $1.date }
  }

  private var selectedDay: DailyPumpingSummary? {
    let date = ChartSelection.day(
      containing: selectedDate, among: days.map(\.date), calendar: calendar)
    return days.first { $0.date == date }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Recent volume by day").font(.headline)
      Text("Last 30 sessions · Daily totals include only these sessions")
        .font(.caption).foregroundStyle(.secondary)
      Chart {
        ForEach(days) { day in
          BarMark(
            x: .value("Day", day.date, unit: .day),
            y: .value(unit.label, unit.fromML(day.totalML).double)
          )
          .foregroundStyle(LogStyle.amber)
          .opacity(selectedDay == nil || selectedDay?.date == day.date ? 1 : 0.35)
          .accessibilityLabel(Text(day.date, format: .dateTime.month(.abbreviated).day().year()))
          .accessibilityValue("\(unit.chartQuantity(day.totalML)) · \(sessionText(day))")
        }
        if let day = selectedDay {
          RuleMark(x: .value("Selected day", day.date, unit: .day))
            .foregroundStyle(.secondary).lineStyle(.init(dash: [3, 3])).zIndex(1)
        }
      }
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
          AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
        }
      }
      .chartYAxisLabel(unit.label)
      .chartDateSelection($selectedDate)
      .frame(height: 220)
      .accessibilityLabel("Recorded pumped volume by day, last 30 sessions")
      .chartSelectionDetails(
        date: selectedDay?.date,
        value: selectedDay.map { unit.chartQuantity($0.totalML) } ?? "",
        detail: selectedDay.map { String(localized: "\(sessionText($0)) shown") } ?? "",
        selection: $selectedDate)

    }
    .environment(\.calendar, calendar)
    .environment(\.timeZone, calendar.timeZone)
    .onChange(of: days.map(\.date)) { selectedDate = nil }
  }

  private func sessionText(_ day: DailyPumpingSummary) -> String {
    day.sessions == 1 ? String(localized: "1 session") : String(localized: "\(day.sessions) sessions")
  }
}
