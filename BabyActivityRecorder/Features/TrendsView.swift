import SwiftUI
import Charts

enum TrendMetric: String, CaseIterable, Identifiable {
    case bottles = "Bottles", diapers = "Diapers", pumping = "Pumping", weight = "Weight"
    case length = "Length / height", headCircumference = "Head circumference"
    var id: Self { self }
    var title: String {
        switch self {
        case .bottles: String(localized: "Bottles")
        case .diapers: String(localized: "Diapers")
        case .pumping: String(localized: "Pumping")
        case .weight: String(localized: "Weight")
        case .length: String(localized: "Length / height")
        case .headCircumference: String(localized: "Head circumference")
        }
    }
    var growthMeasurement: GrowthMeasurementMetric? {
        self == .length ? .length : self == .headCircumference ? .headCircumference : nil
    }
    var isGrowth: Bool { self == .weight || growthMeasurement != nil }
}

struct TrendsView: View {
    @Bindable var store: LogStore
    var settingsPresentation: Binding<Bool>?
    @State private var days: Int
    @State private var routine = false
    @State private var metric: TrendMetric
    @State private var showTable = false
    @State private var childEditor: ChildEditRoute?
    @State private var measurementEditor: LogRoute?
    @AppStorage(WeightUnit.preferenceKey) private var weightUnit: WeightUnit = .kg
    @AppStorage(LengthUnit.preferenceKey) private var measurementUnit: LengthUnit = .cm
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -6, to: .now) ?? .now
    @State private var customEnd = Date.now
    @Environment(\.dynamicTypeSize) private var typeSize
    // Seed the screen's own selection once; subsequent choices belong to the user.
    init(store: LogStore, initialMetric: TrendMetric = .bottles, initialDays: Int = 7, settingsPresentation: Binding<Bool>? = nil) {
        self.store = store
        self.settingsPresentation = settingsPresentation
        self.metric = initialMetric
        self.days = initialDays == 30 ? 30 : 7
    }
    private var timeZone: TimeZone { TimeZone(identifier: store.snapshot.family?.timeZoneIdentifier ?? "") ?? .current }
    private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = timeZone; return value }
    private var end: Date { days == 0 ? min(.now, (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEnd)) ?? customEnd).addingTimeInterval(-0.001)) : .now }
    private var count: Int { days == 0 ? max(1, min(366, (calendar.dateComponents([.day], from: calendar.startOfDay(for: customStart), to: calendar.startOfDay(for: customEnd)).day ?? 0) + 1)) : days }
    private var data: [DailySummary] {
        guard let child = store.selectedChild else { return [] }
        return LogAnalytics.days(activities: store.snapshot.activities, childID: child.id, count: count, now: end, timeZone: timeZone)
    }
    private var entries: [Activity] {
        let childID = store.selectedChild?.id
        let start = data.first?.date ?? .now
        let through = end
        return store.snapshot.activities.filter {
            $0.childID == childID && $0.occurredAt >= start && $0.occurredAt <= through
                && $0.payload.isComplete
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if typeSize.isAccessibilitySize { childHeading }
                    chartControls
                    if days == 0 {
                        LogDatePicker(title: String(localized: "From"), selection: $customStart, range: .distantPast...customEnd, displayedComponents: .date)
                        LogDatePicker(title: String(localized: "Through"), selection: $customEnd, range: customStart...Date.now, displayedComponents: .date)
                    }
                    if routine {
                        if entries.isEmpty { emptyActivity }
                        else {
                            RoutineChart(
                                entries: entries.filter {
                                    [.bottle, .diaper, .breastfeeding].contains($0.payload.kind)
                                }, days: data, calendar: calendar, unit: store.volumeUnit,
                                showTable: typeSize.isAccessibilitySize || showTable
                            ).id(store.selectedChild?.id)
                        }
                    } else {
                        if metric == .pumping {
                            PumpingTrendsView(store: store, dayCount: count, end: end, timeZone: timeZone, showTable: showTable || typeSize.isAccessibilitySize)
                        } else if let measurement = metric.growthMeasurement, let child = store.selectedChild {
                            MeasurementChart(entries: entries, child: child, metric: measurement, unit: measurementUnit,
                                interval: DateInterval(start: data.first?.date ?? end, end: end), calendar: calendar,
                                showTable: showTable || typeSize.isAccessibilitySize, canEdit: store.canEdit,
                                editProfile: { childEditor = ChildEditRoute(child: child) },
                                addMeasurement: { measurementEditor = LogRoute(kind: measurement.kind, childID: child.id) }
                            ).id("\(child.id)-\(measurement.rawValue)")
                        } else if metric == .weight, let child = store.selectedChild {
                            WeightChart(
                                entries: entries, child: child, unit: weightUnit,
                                interval: DateInterval(start: data.first?.date ?? end, end: end),
                                calendar: calendar,
                                showTable: showTable || typeSize.isAccessibilitySize,
                                canEditProfile: store.canEdit,
                                editProfile: { childEditor = ChildEditRoute(child: child) }
                            ).id(child.id)
                        } else if entries.isEmpty { emptyActivity }
                        else {
                            DailyActivityChart(
                                days: data, kind: metric == .bottles ? .bottle : .diaper,
                                unit: store.volumeUnit,
                                showTable: showTable || typeSize.isAccessibilitySize
                            ).id(store.selectedChild?.id)
                        }
                        if !metric.isGrowth {
                            Text("The current day is partial. Days without records mean “no entries.”")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !typeSize.isAccessibilitySize { Toggle("Show data as a list", isOn: $showTable).font(.subheadline) }
                    Text("Calendar days use \(timeZone.identifier.replacingOccurrences(of: "_", with: " ")).")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 24)
                    .frame(maxWidth: 720).frame(maxWidth: .infinity)
            }.background(LogStyle.canvas).navigationTitle("Trends").navigationBarTitleDisplayMode(.inline)
                .environment(\.calendar, calendar).environment(\.timeZone, timeZone)
                .sheet(item: $childEditor) { ChildEditor(store: store, existing: $0.child) }
                .sheet(item: $measurementEditor) { ActivityEditor(store: store, route: $0) }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        if !typeSize.isAccessibilitySize { childHeading }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        SettingsButton(store: store, presentation: settingsPresentation)
                    }
                }
        }
    }
    @ViewBuilder private var childHeading: some View {
        if routine || metric != .pumping {
            ChildPicker(children: store.snapshot.children, selectedID: store.selectedChild?.id) {
                store.selectedChildID = $0
            }
        } else {
            Text("Family pumping").font(.headline)
        }
    }
    private var chartControls: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    periodMenu
                    metricMenu
                    units
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        periodMenu.fixedSize()
                        metricMenu.fixedSize()
                        Spacer(minLength: 0)
                        units
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            periodMenu
                            Spacer(minLength: 0)
                            metricMenu
                        }
                        units.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }.font(.subheadline.weight(.semibold)).buttonStyle(.glass).buttonBorderShape(.capsule)
    }
    @ViewBuilder private var units: some View {
        if !routine && metric == .weight {
            Picker("Weight unit", selection: $weightUnit) {
                ForEach(WeightUnit.allCases) { unit in
                    Text(unit.label).accessibilityLabel(unit.accessibilityLabel).tag(unit)
                }
            }.logPickerStyle().frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 170, alignment: .leading)
                .accessibilityHint("Sets weight units for Trends")
                .accessibilityIdentifier("weightUnit.picker")
        } else if !routine && metric.growthMeasurement != nil {
            Picker("Measurement unit", selection: $measurementUnit) {
                ForEach(LengthUnit.allCases) { Text($0.label).tag($0) }
            }.logPickerStyle().frame(maxWidth: 170).accessibilityIdentifier("growth.units")
        } else if routine || !metric.isGrowth { VolumeUnitPicker(unit: $store.volumeUnit) }
    }
    private var periodMenu: some View {
        Menu {
            Picker("Period", selection: $days) {
                Text("7 days").tag(7); Text("30 days").tag(30); Text("Custom dates").tag(0)
            }
        } label: {
            HStack(spacing: 5) {
                Text(days == 0 ? String(localized: "Custom dates") : String(localized: "\(days) days"))
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }.frame(minHeight: 44)
        }.accessibilityLabel("Chart period, \(days == 0 ? String(localized: "custom dates") : String(localized: "\(days) days"))")
    }
    private var metricMenu: some View {
        Menu {
            Picker("Chart", selection: $metric) {
                ForEach(TrendMetric.allCases) { Text($0.title).tag($0) }
            }.disabled(routine)
            Divider()
            Picker("View", selection: $routine) {
                Text("Daily totals").tag(false); Text("Routine pattern").tag(true)
            }
        } label: {
            HStack(spacing: 5) {
                Text(routine ? String(localized: "Routine") : metric.title)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }.frame(minHeight: 44)
        }.accessibilityLabel("Chart, \(routine ? String(localized: "Routine") : metric.title)")
    }
    private var emptyActivity: some View {
        ContentUnavailableView("Patterns take a little time", systemImage: "chart.xyaxis.line", description: Text("Recorded activity will appear here. A day without entries doesn’t mean nothing happened."))
    }
}

struct DailyActivityChart: View {
    let days: [DailySummary]
    let kind: ActivityKind
    let unit: VolumeUnit
    let showTable: Bool
    @State private var selectedDate: Date?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.calendar) private var calendar
    private var selectedDay: DailySummary? {
        let date = ChartSelection.day(
            containing: selectedDate, among: days.map(\.date), calendar: calendar)
        return days.first { $0.date == date }
    }
    private var series: [String] {
        kind == .bottle ? ([String(localized: "Milk"), String(localized: "Formula")] + (days.contains { $0.summary.unknownML > 0 } ? [String(localized: "Split not recorded")] : [])) : kind == .diaper ? [String(localized: "Pee only"), String(localized: "Poo only"), String(localized: "Both")] : [String(localized: "Breastfeeding")]
    }
    private func color(for label: String) -> Color {
        label == String(localized: "Split not recorded") ? .gray : label == String(localized: "Formula") || label == String(localized: "Poo only") ? LogStyle.amber : label == String(localized: "Both") ? .indigo : LogStyle.blue
    }
    private var title: String { kind == .bottle ? String(localized: "Bottle intake") : kind == .diaper ? String(localized: "Diaper changes") : String(localized: "Time breastfeeding") }
    private var total: String {
        if kind == .bottle {
            return unit.chartQuantity(days.reduce(Decimal(0)) { $0 + $1.summary.totalML })
        }
        if kind == .diaper { return String(localized: "\(days.reduce(0) { $0 + $1.summary.changes }) changes") }
        return LogAnalytics.recordedMinutes(days.reduce(0) { $0 + $1.summary.nursingSeconds })
    }
    var body: some View {
        LogCard {
            VStack(alignment: .leading, spacing: 20) {
                Text(title).font(LogStyle.heading(.title2))
                Text(total).font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit()
                    .logValueTransition(value: total)
                if showTable {
                    ForEach(days) { day in
                        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top))
                        layout {
                            Text(day.date, format: .dateTime.month(.abbreviated).day())
                            if !typeSize.isAccessibilitySize { Spacer() }
                            Text(dayText(day)).multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                        }.font(.subheadline).fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
                        Divider()
                    }
                } else {
                    Chart {
                        ForEach(days) { day in
                            if kind == .bottle {
                                BarMark(x: .value("Day", day.date, unit: .day), y: .value(unit.label, unit.fromML(day.summary.milkML).double)).foregroundStyle(by: .value("Source", String(localized: "Milk")))
                                BarMark(x: .value("Day", day.date, unit: .day), y: .value(unit.label, unit.fromML(day.summary.formulaML).double)).foregroundStyle(by: .value("Source", String(localized: "Formula")))
                                if day.summary.unknownML > 0 {
                                    BarMark(x: .value("Day", day.date, unit: .day), y: .value(unit.label, unit.fromML(day.summary.unknownML).double)).foregroundStyle(by: .value("Source", String(localized: "Split not recorded")))
                                }
                            } else if kind == .diaper {
                                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Changes", day.summary.peeOnly)).foregroundStyle(by: .value("Kind", String(localized: "Pee only")))
                                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Changes", day.summary.pooOnly)).foregroundStyle(by: .value("Kind", String(localized: "Poo only")))
                                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Changes", day.summary.both)).foregroundStyle(by: .value("Kind", String(localized: "Both")))
                            } else {
                                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Minutes", day.summary.nursingSeconds / 60)).foregroundStyle(by: .value("Kind", String(localized: "Breastfeeding")))
                            }
                        }
                        if let day = selectedDay {
                            RuleMark(x: .value("Selected day", day.date, unit: .day))
                                .foregroundStyle(.secondary)
                                .lineStyle(.init(dash: [3, 3]))
                                .zIndex(1)
                        }
                    }
                    .chartForegroundStyleScale(domain: series, mapping: color(for:))
                    .chartYAxis { AxisMarks(position: .leading) }
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: days.count > 7 ? max(1, days.count / 5) : 1)) { _ in AxisValueLabel(format: .dateTime.day()) } }
                    .chartDateSelection($selectedDate).frame(height: 220)
                    .accessibilityLabel(title)
                    .chartSelectionDetails(
                        date: selectedDay?.date, value: selectedDay.map(selectedValue) ?? "",
                        detail: selectedDay.map(dayText) ?? "", selection: $selectedDate)

                }
            }
        }
        .onChange(of: kind) { selectedDate = nil }
        .onChange(of: days.map(\.date)) { selectedDate = nil }
    }
    private func selectedValue(_ day: DailySummary) -> String {
        if kind == .bottle {
            return day.summary.bottles == 0 ? String(localized: "No entries") : unit.chartQuantity(day.summary.totalML)
        }
        if kind == .diaper {
            return day.summary.changes == 0
                ? String(localized: "No entries")
                : String(localized: "\(day.summary.changes) changes")
        }
        return LogAnalytics.recordedMinutes(day.summary.nursingSeconds)
    }
    private func dayText(_ day: DailySummary) -> String {
        if kind == .bottle {
            return day.summary.bottles == 0
                ? String(localized: "No bottles recorded")
                : String(localized: "\(unit.chartQuantity(day.summary.milkML)) milk · \(unit.chartQuantity(day.summary.formulaML)) formula")
                    + (day.summary.unknownML > 0
                        ? String(localized: "\n\(unit.chartQuantity(day.summary.unknownML)) split not recorded") : "")
                    + "\n" + String(localized: "\(day.summary.bottles) feeds")
        }
        if kind == .diaper {
            return day.summary.changes == 0
                ? String(localized: "No diapers recorded")
                : String(localized: "\(day.summary.peeOnly) pee only · \(day.summary.pooOnly) poo only · \(day.summary.both) both\n\(day.summary.wet) wet · \(day.summary.soiled) soiled")
        }
        return day.summary.nursingSessions == 0 ? String(localized: "No entries") : String(localized: "\(LogAnalytics.recordedMinutes(day.summary.nursingSeconds)) · \(day.summary.nursingSessions) sessions")
    }
}

struct RoutineChart: View {
    let entries: [Activity]
    let days: [DailySummary]
    let calendar: Calendar
    let unit: VolumeUnit
    let showTable: Bool
    @State private var selectedDate: Date?
    private var selectedDay: DailySummary? {
        let date = ChartSelection.day(
            containing: selectedDate, among: days.map(\.date), calendar: calendar)
        return days.first { $0.date == date }
    }
    private func hour(_ date: Date) -> Double {
        Double(calendar.component(.hour, from: date)) + Double(calendar.component(.minute, from: date)) / 60
    }
    var body: some View {
        LogCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Your days, together").font(LogStyle.heading(.title2))
                Text("Each mark is a recorded moment. No schedule to keep up with.").font(.subheadline).foregroundStyle(.secondary)
                if showTable {
                    ForEach(entries) { entry in
                        Label("\(entry.occurredAt.formatted(date: .abbreviated, time: .shortened)) · \(entry.payload.kind.title)", systemImage: entry.payload.kind.symbol)
                            .font(.subheadline)
                    }
                } else {
                    Chart {
                        ForEach(entries) { entry in
                            PointMark(
                                x: .value("Hour of day", hour(entry.occurredAt)),
                                y: .value(
                                    "Day", calendar.startOfDay(for: entry.occurredAt), unit: .day)
                            )
                            .foregroundStyle(by: .value("Activity", entry.payload.kind.title))
                            .symbol(by: .value("Activity", entry.payload.kind.title))
                            .symbolSize(65)
                            .accessibilityLabel("\(entry.payload.kind.title), \(entry.occurredAt.formatted(date: .abbreviated, time: .shortened))")
                        }
                        if let day = selectedDay {
                            RuleMark(y: .value("Selected day", day.date, unit: .day))
                                .foregroundStyle(.secondary)
                                .lineStyle(.init(dash: [3, 3]))
                                .zIndex(1)
                        }
                    }
                    .chartXScale(domain: 0...24)
                    .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 24]) { value in AxisGridLine(); AxisValueLabel { if let h = value.as(Int.self) { Text(hourLabel(h)) } } } }
                    .chartYAxis { AxisMarks(position: .leading, values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                    .chartForegroundStyleScale([String(localized: "Bottle"): LogStyle.milk, String(localized: "Diaper"): LogStyle.formula, String(localized: "Breastfeed"): Color.indigo])
                    .chartSymbolScale([
                        String(localized: "Bottle"): .circle, String(localized: "Diaper"): .square, String(localized: "Breastfeed"): .triangle,
                    ])
                    .chartLegend(.hidden)
                    .chartDateSelection($selectedDate, vertical: true)
                    .frame(height: 320)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) { legendItems }.fixedSize()
                        VStack(alignment: .leading, spacing: 6) { legendItems }
                    }
                    .chartSelectionDetails(
                        date: selectedDay?.date,
                        value: selectedDay.map { $0.summary.bottles == 0
                            ? String(localized: "No bottles recorded") : String(localized: "\(unit.chartQuantity($0.summary.totalML)) bottled") } ?? "",
                        detail: selectedDay.map {
                            String(localized: "\($0.summary.bottles) feeds") + " · "
                                + String(localized: "\($0.summary.changes) diaper changes") + "\n"
                                + String(localized: "\(LogAnalytics.recordedMinutes($0.summary.nursingSeconds)) breastfeeding")
                        } ?? "", selection: $selectedDate)

                }
            }
        }
        .onChange(of: days.map(\.date)) { selectedDate = nil }
    }

    // A single legend carries both shape and color. Separate automatic scales
    // can produce duplicate legends, which obscure the chart's meaning.
    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("j")
        return formatter.string(from: Date(timeIntervalSinceReferenceDate: Double(hour % 24) * 3600))
    }
    @ViewBuilder private var legendItems: some View {
        legendItem(String(localized: "Bottle"), symbol: "circle.fill", color: LogStyle.milk)
        legendItem(String(localized: "Diaper"), symbol: "square.fill", color: LogStyle.formula)
        legendItem(String(localized: "Breastfeed"), symbol: "triangle.fill", color: .indigo)
    }

    private func legendItem(_ title: String, symbol: String, color: Color) -> some View {
        Label {
            Text(title).foregroundStyle(LogStyle.muted)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }.font(.caption)
    }
}
