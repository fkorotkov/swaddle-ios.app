import SwiftUI
import Charts

struct PumpingTrendsView: View {
    let store: LogStore
    let dayCount: Int
    let end: Date
    let timeZone: TimeZone
    let showTable: Bool
    @State private var selectedMotherID: UUID?

    private var mothers: [Caregiver] { store.snapshot.pumpingHistoryCaregivers }
    private var selectedMother: Caregiver? {
        mothers.first { $0.id == selectedMotherID }
            ?? mothers.first { $0.id == store.caregiverID }
            ?? mothers.first { store.snapshot.record($0.id)?.isDeleted == false && $0.isMother }
            ?? mothers.first
    }

    var body: some View {
        if let family = store.snapshot.family, let mother = selectedMother {
            if mothers.count > 1 {
                Picker("Pumping profile", selection: Binding(get: { mother.id }, set: { selectedMotherID = $0 })) {
                    ForEach(mothers) { person in
                        Text(
                            store.snapshot.record(person.id)?.isDeleted == true
                                ? String(localized: "\(person.name) (deleted profile)") : person.name
                        ).tag(person.id)
                    }
                }.pickerStyle(.menu).frame(minHeight: 44)
            }
            let days = LogAnalytics.pumpingDays(sessions: store.snapshot.pumps, familyID: family.id,
                                               motherID: mother.id, count: dayCount, now: end, timeZone: timeZone)
            DailyPumpingChart(days: days, caregiverName: mother.name, unit: store.volumeUnit, showTable: showTable,
                sessions: store.snapshot.pumps.filter { $0.motherID == mother.id && $0.familyID == family.id })
                .id(mother.id)
            NavigationLink { PumpHistoryView(store: store, mother: mother) } label: {
                Label("All pumping sessions", systemImage: "list.bullet")
                    .frame(minHeight: 44)
            }
            if store.snapshot.record(mother.id)?.isDeleted == true {
                Text("Deleted profile · History kept").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            ContentUnavailableView("A place for pumping", systemImage: "drop.halffull",
                                   description: Text("Add a pumping profile in Settings to see daily volumes here."))
        }
    }
}

struct DailyPumpingChart: View {
    let days: [DailyPumpingSummary]
    let caregiverName: String
    let unit: VolumeUnit
    let showTable: Bool
    var sessions: [PumpSession] = []
    @Environment(\.careWideLayout) private var wide
    @State private var selectedDate: Date?
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var typeSize
    private var totalML: Decimal { days.reduce(0) { $0 + $1.totalML } }
    private var sessionCount: Int { days.reduce(0) { $0 + $1.sessions } }
    private var selectedDay: DailyPumpingSummary? {
        let date = ChartSelection.day(
            containing: selectedDate, among: days.map(\.date), calendar: calendar)
        return days.first { $0.date == date }
    }

    var body: some View {
        LogCard {
            VStack(alignment: .leading, spacing: 20) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        heading.fixedSize()
                        Spacer(minLength: 0)
                        if sessionCount > 0 { amount.fixedSize() }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        heading
                        if sessionCount > 0 { amount }
                    }
                }
                if sessionCount == 0 {
                    Text("No pumping entries in this period.").font(.title3.weight(.medium))
                    Text("Recorded sessions for \(caregiverName) will appear here.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    if showTable {
                        ForEach(days) { day in
                            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top))
                            layout {
                                Text(day.date, format: .dateTime.month(.abbreviated).day())
                                if !typeSize.isAccessibilitySize { Spacer() }
                                Text(dayText(day)).multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                            }.font(.subheadline).fixedSize(horizontal: false, vertical: true)
                                .accessibilityElement(children: .combine)
                            Divider()
                        }
                    } else {
                        Chart {
                            ForEach(days) { day in
                                BarMark(x: .value("Day", day.date, unit: .day),
                                        y: .value("Pumped, \(unit.label)", unit.fromML(day.totalML).double))
                                    .foregroundStyle(LogStyle.amber)
                                    .opacity(selectedDay == nil || selectedDay?.date == day.date ? 1 : 0.35)
                                    .cornerRadius(4)
                                    .accessibilityLabel(Text(day.date, format: .dateTime.month(.abbreviated).day()))
                                    .accessibilityValue(dayText(day))
                            }
                            if let day = selectedDay {
                                RuleMark(x: .value("Selected day", day.date, unit: .day))
                                    .foregroundStyle(.secondary).lineStyle(.init(dash: [3, 3]))
                                    .zIndex(1)
                            }
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .chartYAxisLabel(unit.label)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: days.count > 7 ? max(1, days.count / 5) : 1)) { _ in
                                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            }
                        }
                        .chartDateSelection($selectedDate).frame(height: wide ? 340 : 220)
                        .accessibilityLabel("Daily pumped volume for \(caregiverName)")
                        .chartSelectionDetails(
                            date: selectedDay?.date,
                            value: selectedDay.map { $0.sessions == 0
                                ? String(localized: "No entries") : unit.chartQuantity($0.totalML) } ?? "",
                            detail: selectedDay.map { $0.sessions == 0
                                ? String(localized: "No pumping recorded")
                                : String(localized: "\($0.sessions) sessions") + " · " + caregiverName } ?? "",
                            selection: $selectedDate,
                            records: selectedDay.map { day in
                                sessions.filter { calendar.isDate($0.occurredAt, inSameDayAs: day.date) }
                                    .sorted { $0.occurredAt < $1.occurredAt }
                                    .map { ChartSelectionRecord(id: $0.id, date: $0.occurredAt, value: unit.chartQuantity($0.totalML)) }
                            } ?? [])

                    }
                }
                Text("Shared family record · Separate from bottle intake")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: days.map(\.date)) { selectedDate = nil }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Pumped", systemImage: "drop").font(.headline).foregroundStyle(LogStyle.amber)
            Text(caregiverName).font(.subheadline).foregroundStyle(LogStyle.muted)
        }
    }
    private var amount: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(unit.chartQuantity(totalML)).font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit().logValueTransition(value: unit.chartQuantity(totalML))
            Text(sessionCount == 1 ? String(localized: "1 session") : String(localized: "\(sessionCount) sessions"))
                .font(.caption).foregroundStyle(LogStyle.muted)
        }.accessibilityElement(children: .combine)
    }
    private func dayText(_ day: DailyPumpingSummary) -> String {
        guard day.sessions > 0 else { return String(localized: "No entries") }
        return String(localized: "\(unit.chartQuantity(day.totalML)) · ")
            + (day.sessions == 1 ? String(localized: "1 session") : String(localized: "\(day.sessions) sessions"))
    }
}
