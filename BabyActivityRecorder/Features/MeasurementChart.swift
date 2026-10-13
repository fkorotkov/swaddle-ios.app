import Charts
import SwiftUI

struct MeasurementChart: View {
  let child: ChildProfile
  let metric: GrowthMeasurementMetric
  let unit: LengthUnit
  let series: MeasurementGrowthSeries
  let showTable: Bool
  let canEdit: Bool
  let editProfile: () -> Void
  let addMeasurement: () -> Void
  @Environment(\.careWideLayout) private var wide
  @State private var selectedDate: Date?
  @Environment(\.babyPalette) private var palette
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .subheadline) private var readoutHeight = 164

  init(entries: [Activity], child: ChildProfile, metric: GrowthMeasurementMetric, unit: LengthUnit,
    interval: DateInterval, calendar: Calendar, showTable: Bool, canEdit: Bool,
    editProfile: @escaping () -> Void, addMeasurement: @escaping () -> Void) {
    self.child = child; self.metric = metric; self.unit = unit
    self.series = MeasurementGrowthSeries(entries: entries, child: child, metric: metric,
      interval: interval, calendar: calendar, now: .now)
    self.showTable = showTable; self.canEdit = canEdit
    self.editProfile = editProfile; self.addMeasurement = addMeasurement
  }
  private var selected: MeasurementGrowthSeries.Measurement? {
    let date = ChartSelection.measurement(near: selectedDate, among: series.measurements.map(\.date))
    return series.measurements.first { $0.date == date }
  }
  private func quantity(_ centimeters: Double) -> String { unit.quantity(Decimal(centimeters)) }
  private func plotted(_ centimeters: Double) -> Double { unit.fromCentimeters(Decimal(centimeters)).double }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      LogCard {
        VStack(alignment: .leading, spacing: 18) {
          HStack(alignment: .top, spacing: 12) {
            Text(metric.title).font(LogStyle.heading(.title2))
              .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if canEdit {
              Button("Add measurement", systemImage: "plus", action: addMeasurement)
                .labelStyle(.iconOnly).font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44).background(.primary.opacity(0.06), in: .circle)
                .buttonStyle(LogPressStyle()).accessibilityIdentifier("growth.addMeasurement")
            }
          }
          if let latest = series.measurements.last {
            let point = selected ?? latest
            CareChartColumns(readoutFirstWhenCompact: true, showsPlot: !showTable) {
              if !showTable {
                plot
                if !series.curves.isEmpty {
                  WeightReferenceGuide()
                }
                Label("Tap a measurement for its age and percentiles", systemImage: "hand.tap")
                  .font(.caption).foregroundStyle(LogStyle.muted)
              }
            } detail: {
              VStack(alignment: .leading, spacing: 18) {
                readout(point)
                if let comparison = point.whoAgeComparison {
                  AgePercentileComparisonView(reference: comparison.reference,
                    actualPercentile: comparison.actual.percentile, actualDays: comparison.actual.days,
                    correctedPercentile: comparison.corrected?.percentile, correctedDays: comparison.correctedDays,
                    measurementName: metric.comparisonName)
                }
                if let unavailable = point.unavailable {
                  Text(unavailable).font(.subheadline).foregroundStyle(LogStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
            }
          } else {
            Text("No \(metric.comparisonName) entries in this period.").foregroundStyle(LogStyle.muted)
          }
          if child.birthDate == nil || child.effectiveGrowthReferenceSex == nil {
            if canEdit {
              Button("Set up growth reference", systemImage: "slider.horizontal.3", action: editProfile)
                .frame(minHeight: 44).buttonStyle(.bordered)
            } else {
              Text("A family editor can add a birth date and choose a growth reference in the child’s profile.")
                .font(.subheadline).foregroundStyle(LogStyle.muted)
            }
          }
        }
      }
      if !series.measurements.isEmpty {
        Text("Measurements").font(LogStyle.heading(.title3))
        Text("Lines connect measurements; they don’t estimate values between entries.")
          .font(.caption).foregroundStyle(LogStyle.muted)
        ForEach(series.measurements.reversed()) { point in
          VStack(alignment: .leading, spacing: 6) {
            Text(point.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
              .font(.caption).foregroundStyle(LogStyle.muted)
            Text(quantity(point.centimeters)).font(.headline).monospacedDigit()
            if metric == .length { Text(point.position.measurementTitle + " · " + point.position.title).font(.caption).foregroundStyle(LogStyle.muted) }
            if let reading = point.reading, point.whoAgeComparison == nil {
              Text(reading.percentileLabel).font(.subheadline)
              Text(reading.context).font(.caption).foregroundStyle(LogStyle.muted)
            } else if let unavailable = point.unavailable, point.whoAgeComparison == nil {
              Text(unavailable).font(.caption).foregroundStyle(LogStyle.muted)
            }
            if let reading = point.reading { adjustment(reading) }
            if let comparison = point.whoAgeComparison { Text(comparisonSummary(comparison)).font(.caption).foregroundStyle(LogStyle.muted) }
          }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
          Divider()
        }
      }
      about
    }
    .onChange(of: child) { selectedDate = nil }
    .onChange(of: series.measurements.map(\.id)) { selectedDate = nil }
    .onChange(of: showTable) { selectedDate = nil }
    #if DEBUG && targetEnvironment(simulator)
      .task {
        if MotionReview.isRequested && MotionReview.has("--growth-selected") {
          await Task.yield(); selectedDate = series.measurements.dropFirst().first?.date
        }
      }
    #endif
  }
  private var plot: some View {
    Chart {
      ForEach(series.curves) { curve in
        ForEach(curve.points) { point in
          LineMark(x: .value("Date", point.date), y: .value(metric.title, plotted(point.centimeters)),
            series: .value("Growth reference", curve.id))
            .foregroundStyle(LogStyle.muted.opacity(curve.label == "50th" ? 0.85 : 0.55))
            .lineStyle(.init(lineWidth: 1, dash: curve.label == "50th" ? [6, 4] : [2, 4]))
            .interpolationMethod(.linear).accessibilityHidden(true)
        }
      }
      ForEach(series.measurements) { point in
        LineMark(x: .value("Date", point.date), y: .value(metric.title, plotted(point.chartedCentimeters)),
          series: .value("Recorded", metric.rawValue))
          .foregroundStyle(palette.accent).lineStyle(.init(lineWidth: 2)).interpolationMethod(.linear)
          .accessibilityHidden(true)
        PointMark(x: .value("Date", point.date), y: .value(metric.title, plotted(point.chartedCentimeters)))
          .foregroundStyle(palette.accent).symbolSize(55)
          .accessibilityLabel(Text(point.date, format: .dateTime.month(.abbreviated).day().hour().minute()))
          .accessibilityValue("\(quantity(point.centimeters)), \(point.reading.map { "\($0.percentileLabel), \($0.context)" } ?? String(localized: "percentile unavailable")). \(point.whoAgeComparison.map(comparisonSummary) ?? "")")
      }
      if let selected {
        RuleMark(x: .value("Selected measurement", selected.date)).foregroundStyle(palette.accent.opacity(0.5))
          .lineStyle(.init(dash: [3, 3])).accessibilityHidden(true)
        PointMark(x: .value("Date", selected.date), y: .value(metric.title, plotted(selected.chartedCentimeters)))
          .foregroundStyle(palette.accent).symbolSize(110).accessibilityHidden(true)
      }
    }
    .chartYAxisLabel(unit.label, position: .topLeading)
    .chartYScale(domain: .automatic(includesZero: false))
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) { _ in
        AxisGridLine(); AxisValueLabel(format: .dateTime.month(.abbreviated).day())
      }
    }
    .chartDateSelection($selectedDate, byDay: false)
    .frame(height: wide ? 340 : 240).accessibilityLabel("\(metric.title) and growth reference percentiles")
  }
  private func readout(_ point: MeasurementGrowthSeries.Measurement) -> some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 6) {
        Text(selected == nil ? String(localized: "Latest recorded") : String(localized: "Selected measurement"))
          .font(.caption.weight(.semibold)).foregroundStyle(LogStyle.muted)
        Text(quantity(point.centimeters)).font(.system(.largeTitle, design: .rounded, weight: .bold))
          .monospacedDigit().logValueTransition(value: quantity(point.centimeters))
        Text(point.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
          .font(.caption).foregroundStyle(LogStyle.muted)
        if metric == .length { Text(point.position.measurementTitle + " · " + point.position.title).font(.caption).foregroundStyle(LogStyle.muted) }
        if let reading = point.reading, point.whoAgeComparison == nil {
          Text(reading.percentileLabel).font(.headline)
          Text(reading.context).font(.caption).foregroundStyle(LogStyle.muted)
        } else if point.whoAgeComparison == nil { Text("Percentile unavailable").font(.caption).foregroundStyle(LogStyle.muted) }
        if let reading = point.reading { adjustment(reading) }
      }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
      Spacer(minLength: 0)
      Button("Dismiss chart details", systemImage: "xmark") { selectedDate = nil }
        .labelStyle(.iconOnly).font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44)
        .background(.primary.opacity(0.06), in: .circle).buttonStyle(.plain)
        .opacity(selected == nil ? 0 : 1).disabled(selected == nil).accessibilityHidden(selected == nil)
        .accessibilityIdentifier("chart.details.dismiss")
    }.frame(minHeight: point.whoAgeComparison == nil ? readoutHeight : readoutHeight * 0.65, alignment: .topLeading)
      .accessibilityAction(.escape) { selectedDate = nil }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected?.id)
      .sensoryFeedback(.selection, trigger: selected?.id) { _, new in new != nil }
  }
  @ViewBuilder private func adjustment(_ reading: MeasurementForAge.Reading) -> some View {
    if reading.adjustmentCM != 0 {
      Text("WHO compares this as \(quantity(reading.referenceCentimeters)) \(reading.adjustmentCM > 0 ? String(localized: "lying-down length") : String(localized: "standing height")). Your recorded value is unchanged.")
        .font(.caption).foregroundStyle(LogStyle.muted)
    }
  }
  private func comparisonSummary(_ comparison: MeasurementForAge.AgeComparison) -> String {
    let corrected = comparison.corrected.map { String(localized: "\($0.percentileLabel) at \(ChildAge.duration($0.days))") } ?? String(localized: "not available before due date")
    return String(localized: "WHO \(comparison.reference.title) · Corrected age: \(corrected)\nActual age: \(comparison.actual.percentileLabel) at \(ChildAge.duration(comparison.actual.days)) since birth")
  }
  private var about: some View {
    DisclosureGroup("About growth percentiles") {
      VStack(alignment: .leading, spacing: 12) {
        Text("\(metric.title) is compared with children of the same age and sex in the named reference. The midpoint is not a target.")
        PercentileRangeExplanation()
        Text("Swaddle uses WHO Child Growth Standards. For a known preterm birth, the chart uses corrected age until the second birthday, then age since birth. These comparisons cover birth through the fifth birthday. Recorded measurements remain visible outside the reference range.")
        if metric == .length {
          Text("WHO compares lying-down length through day 730 and standing height from day 731. When the recorded position differs, WHO adds or subtracts 0.7 cm for the comparison and plotted point. The original entry is never changed.")
        }
        Text("For a preterm baby under two, additional WHO details compare corrected and actual age. Before the due date, corrected-age WHO is unavailable. Reference curves are separated when the standard, age basis, or length/height basis changes.")
        Text("The chart’s dashed lines use WHO with corrected age for a known preterm birth under two. The actual-age value is a separately labeled comparison. These comparisons are rounded estimates, not a diagnosis.")
        Link("WHO \(metric.title) standards", destination: metric.referenceURL).frame(minHeight: 44)
        if canEdit { Button("Edit growth reference", action: editProfile).frame(minHeight: 44) }
      }.font(.footnote).foregroundStyle(LogStyle.muted).padding(.top, 12)
    }.font(.subheadline.weight(.medium))
  }
}
