import Charts
import SwiftUI

struct WeightChart: View {
  let child: ChildProfile
  let unit: WeightUnit
  let series: WeightGrowthSeries
  let showTable: Bool
  let canEditProfile: Bool
  let editProfile: () -> Void
  @State private var selectedDate: Date?
  @Environment(\.babyPalette) private var palette
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .subheadline) private var readoutHeight = 164

  init(
    entries: [Activity], child: ChildProfile, unit: WeightUnit, interval: DateInterval, calendar: Calendar,
    showTable: Bool, canEditProfile: Bool, editProfile: @escaping () -> Void
  ) {
    self.child = child
    self.unit = unit
    self.series = WeightGrowthSeries(
      entries: entries, child: child, interval: interval, calendar: calendar, now: .now)
    self.showTable = showTable
    self.canEditProfile = canEditProfile
    self.editProfile = editProfile
    self.selectedDate = nil
  }

  private var selected: WeightGrowthSeries.Measurement? {
    let date = ChartSelection.measurement(
      near: selectedDate, among: series.measurements.map(\.date))
    return series.measurements.first { $0.date == date }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      LogCard {
        VStack(alignment: .leading, spacing: 18) {
          Text("Growing, at their pace").font(LogStyle.heading(.title2))
          if let latest = series.measurements.last {
            readout(selected ?? latest)
            if let comparison = (selected ?? latest).whoAgeComparison {
              WeightAgeComparisonView(comparison: comparison)
            }
            if let unavailable = (selected ?? latest).unavailable {
              Text(unavailable).font(.subheadline).foregroundStyle(LogStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            if !showTable {
              plot
              if !series.curves.isEmpty {
                WeightReferenceGuide()
              }
              Label("Tap a measurement for its age and percentiles", systemImage: "hand.tap")
                .font(.caption).foregroundStyle(LogStyle.muted)
            }
          } else {
            Text("No weight entries in this period.").foregroundStyle(LogStyle.muted)
          }
          if child.birthDate == nil || child.effectiveGrowthReferenceSex == nil {
            if canEditProfile {
              Button(
                "Set up growth reference", systemImage: "slider.horizontal.3", action: editProfile
              )
              .frame(minHeight: 44).buttonStyle(.bordered).accessibilityIdentifier("growth.setup")
            } else {
              Text(
                "A family editor can add a birth date and choose a growth reference in the child’s profile."
              )
              .font(.subheadline).foregroundStyle(LogStyle.muted)
            }
          }
        }
      }
      if !series.measurements.isEmpty {
        Text("Measurements").font(LogStyle.heading(.title3))
        Text("Lines connect recorded weights; they don’t estimate weights between entries.")
          .font(.caption).foregroundStyle(LogStyle.muted)
        ForEach(series.measurements.reversed()) { point in
          // The full value is present in the list, including when the chart is hidden for large text.
          VStack(alignment: .leading, spacing: 6) {
            Text(point.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
              .font(.caption).foregroundStyle(LogStyle.muted)
            Text(weight(point)).font(.headline).monospacedDigit()
            if let reading = point.reading, point.whoAgeComparison == nil {
              Text(reading.percentileLabel).font(.subheadline)
              Text(reading.context).font(.caption).foregroundStyle(LogStyle.muted)
            } else if let unavailable = point.unavailable, point.whoAgeComparison == nil {
              Text(unavailable).font(.caption).foregroundStyle(LogStyle.muted)
            }
            if let comparison = point.whoAgeComparison {
              Text(comparisonSummary(comparison))
                .font(.caption).foregroundStyle(LogStyle.muted)
            }
          }.fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
          Divider()
        }
      }
      DisclosureGroup("About growth percentiles") {
        VStack(alignment: .leading, spacing: 12) {
          Text(
            "Weight-for-age compares a measurement with children of the same age in the named reference. The 50th percentile is the middle of that reference, not a target."
          )
          PercentileRangeExplanation()
          Text(
            "Swaddle uses WHO Child Growth Standards. For a known preterm birth, the chart uses corrected age, counted from the estimated due date. For term births, it uses age since birth. Weight comparisons stop at the second birthday."
          )
          Text(
            "For a preterm baby, the WHO comparison also shows the same weight on the standard infant reference in two ways. Corrected age counts from the estimated due date; actual age counts from birth, without adjusting for prematurity. Both use age on the measurement date. Corrected-age WHO values begin on the due date; they are unavailable before then."
          )
          Text(
            "The chart’s dashed lines use WHO with corrected age for a known preterm birth. The actual-age value is a separately labeled comparison. Different age choices can give different percentiles for the same weight."
          )
          Text(
            "Percentiles are rounded estimates, not a diagnosis. Your pediatrician considers the full growth pattern and other measurements."
          )
          Link(
            "WHO Child Growth Standards",
            destination: URL(
              string: "https://www.who.int/tools/child-growth-standards/standards/weight-for-age")!
          )
          .frame(minHeight: 44)
          if canEditProfile {
            Button("Edit growth reference", action: editProfile).frame(minHeight: 44)
          }
        }.font(.footnote).foregroundStyle(LogStyle.muted).padding(.top, 12)
      }.font(.subheadline.weight(.medium))
    }
    .onChange(of: child) { clearSelection() }
    .onChange(of: series.measurements.map(\.id)) { clearSelection() }
    .onChange(of: showTable) { clearSelection() }
    #if DEBUG && targetEnvironment(simulator)
      // Charts initializes its selection when mounted. Seed the visual fixture afterward.
      .task {
        if MotionReview.isRequested && MotionReview.has("--growth-selected") {
          await Task.yield()
          selectedDate = series.measurements.dropFirst().first?.date
        }
      }
    #endif
  }

  private var plot: some View {
    Chart {
      ForEach(series.curves) { curve in
        ForEach(curve.points) { point in
          LineMark(
            x: .value("Date", point.date), y: .value("Weight", unit.fromKilograms(point.kilograms)),
            series: .value("Growth reference", curve.id)
          )
          .foregroundStyle(LogStyle.muted.opacity(curve.label == "50th" ? 0.85 : 0.55))
          .lineStyle(.init(lineWidth: 1, dash: curve.label == "50th" ? [6, 4] : [2, 4]))
          .interpolationMethod(.linear).accessibilityHidden(true)
        }
      }
      ForEach(series.measurements) { point in
        LineMark(
          x: .value("Date", point.date), y: .value("Weight", unit.fromKilograms(point.kilograms)),
          series: .value("Recorded", "Weight")
        )
        .foregroundStyle(palette.accent).lineStyle(.init(lineWidth: 2)).interpolationMethod(.linear)
        .accessibilityHidden(true)
        PointMark(x: .value("Date", point.date), y: .value("Weight", unit.fromKilograms(point.kilograms)))
          .foregroundStyle(palette.accent).symbolSize(55)
          .accessibilityLabel(
            Text(point.date, format: .dateTime.month(.abbreviated).day().hour().minute())
          )
          .accessibilityValue(
            "\(weight(point)), \(point.reading.map { "\($0.percentileLabel), \($0.context)" } ?? String(localized: "percentile unavailable")). \(point.whoAgeComparison.map(comparisonSummary) ?? "")")
      }
      if let selected {
        RuleMark(x: .value("Selected measurement", selected.date))
          .foregroundStyle(palette.accent.opacity(0.5)).lineStyle(.init(dash: [3, 3]))
          .accessibilityHidden(true)
        PointMark(x: .value("Date", selected.date), y: .value("Weight", unit.fromKilograms(selected.kilograms)))
          .foregroundStyle(palette.accent).symbolSize(110).accessibilityHidden(true)
      }
    }
    .chartYAxisLabel(unit.label, position: .topLeading)
    .chartYScale(domain: .automatic(includesZero: false))
    .chartYAxis {
      AxisMarks(values: .automatic(desiredCount: 4, roundLowerBound: false, roundUpperBound: false)) { value in
        AxisGridLine()
        AxisTick()
        if let weight = value.as(Double.self) {
          AxisValueLabel { Text(unit.axisLabel(weight)) }
        }
      }
    }
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) { _ in
        AxisGridLine()
        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
      }
    }
    .chartDateSelection($selectedDate, byDay: false)
    // Rebuild chart scales on a unit change; selection stays in the parent readout.
    .id(unit)
    .frame(height: 240).accessibilityLabel("Weight and growth reference percentiles")
  }

  private func readout(_ point: WeightGrowthSeries.Measurement) -> some View {
    HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 6) {
        Text(selected == nil ? String(localized: "Latest recorded") : String(localized: "Selected measurement"))
          .font(.caption.weight(.semibold)).foregroundStyle(LogStyle.muted)
        Text(weight(point)).font(.system(.largeTitle, design: .rounded, weight: .bold))
          .monospacedDigit().logValueTransition(value: weight(point))
        Text(point.date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
          .font(.caption).foregroundStyle(LogStyle.muted)
        if let reading = point.reading, point.whoAgeComparison == nil {
          Text(reading.percentileLabel).font(.headline)
          VStack(alignment: .leading, spacing: 3) {
            Text(reading.age.label)
            Text(reading.referenceLabel)
          }.font(.caption).foregroundStyle(LogStyle.muted)
        } else if point.whoAgeComparison == nil {
          Text("Percentile unavailable").font(.caption).foregroundStyle(LogStyle.muted)
        }
      }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
      Spacer(minLength: 0)
      // Reserve the close target even when showing the latest value, so selection never reflows text.
      Button("Dismiss chart details", systemImage: "xmark", action: clearSelection)
        .labelStyle(.iconOnly).font(.system(size: 17, weight: .semibold))
        .frame(width: 44, height: 44)
        .background(.primary.opacity(0.06), in: .circle).buttonStyle(.plain)
        .opacity(selected == nil ? 0 : 1).disabled(selected == nil)
        .accessibilityHidden(selected == nil).accessibilityIdentifier("chart.details.dismiss")
    }.frame(minHeight: point.whoAgeComparison == nil ? readoutHeight : readoutHeight * 0.65, alignment: .topLeading)
      .accessibilityAction(.escape, clearSelection)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected?.id)
      .sensoryFeedback(.selection, trigger: selected?.id) { _, new in new != nil }
  }

  private func clearSelection() { selectedDate = nil }
  private func comparisonSummary(_ comparison: WHOWeightForAge.AgeComparison) -> String {
    let corrected = comparison.corrected.map {
      String(localized: "\($0.percentileLabel) at \(ChildAge.duration($0.age.days))")
    } ?? String(localized: "not available before due date")
    return String(localized: "WHO \(comparison.actual.reference.title) · Corrected age: \(corrected)\nActual age: \(comparison.actual.percentileLabel) at \(ChildAge.duration(comparison.actual.age.days)) since birth")
  }
  private func weight(_ point: WeightGrowthSeries.Measurement) -> String {
    unit.quantity(point.kilograms)
  }
}

struct WeightReferenceGuide: View {
  var body: some View {
    DisclosureGroup {
      PercentileRangeExplanation().padding(.top, 8)
    } label: {
      Text("What do the lines mean?")
        .fontWeight(.medium).frame(minHeight: 44, alignment: .leading)
    }
    .accessibilityIdentifier("growth.rangeExplanation")
    .font(.caption).foregroundStyle(LogStyle.muted)
    .fixedSize(horizontal: false, vertical: true)
  }
}

struct PercentileRangeExplanation: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Lower dotted line (3rd): about 3 out of 100 children in this reference have a smaller measurement, and 97 have a larger one.")
      Text("Dashed middle line (50th): half have a smaller measurement and half have a larger one. This is the midpoint, not a goal.")
      Text("Upper dotted line (97th): about 97 out of 100 have a smaller measurement, and 3 have a larger one.")
      Text("These comparisons use the same age and sex. The lines are not boundaries between healthy and unhealthy growth.")
    }
    .fixedSize(horizontal: false, vertical: true)
  }
}

#if DEBUG
#Preview("Growth reference guide · Dark", traits: .fixedLayout(width: 375, height: 500)) {
  VStack {
    LogCard { WeightReferenceGuide() }
    Spacer()
  }
  .padding(16).background(LogStyle.canvas).foregroundStyle(LogStyle.ink)
  .tint(LogStyle.forest).preferredColorScheme(.dark)
}

#Preview("Growth reference explanation · Large text", traits: .fixedLayout(width: 375, height: 2200)) {
  VStack {
    LogCard { PercentileRangeExplanation().font(.footnote).foregroundStyle(LogStyle.muted) }
    Spacer()
  }
  .padding(16).background(LogStyle.canvas).foregroundStyle(LogStyle.ink)
  .dynamicTypeSize(.accessibility5).preferredColorScheme(.light)
}
#endif
