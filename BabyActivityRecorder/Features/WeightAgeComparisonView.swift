import SwiftUI

/// Both columns always describe the same selected weight and measurement date.
struct WeightAgeComparisonView: View {
  let comparison: WHOWeightForAge.AgeComparison
  var body: some View {
    AgePercentileComparisonView(reference: comparison.actual.reference,
      actualPercentile: comparison.actual.percentile, actualDays: comparison.actual.age.days,
      correctedPercentile: comparison.corrected?.percentile, correctedDays: comparison.correctedDays,
      measurementName: String(localized: "weight"))
  }
}

struct AgePercentileComparisonView: View {
  let reference: GrowthReferenceSex
  let actualPercentile: Double
  let actualDays: Int
  let correctedPercentile: Double?
  let correctedDays: Int
  let measurementName: String
  @Environment(\.dynamicTypeSize) private var typeSize

  private var layout: AnyLayout {
    typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Divider()
      Text("WHO comparison · \(reference.title)")
        .font(.caption.weight(.semibold)).foregroundStyle(LogStyle.muted)
      layout {
        value(
          title: String(localized: "Corrected age"), percentile: correctedPercentile,
          age: correctedPercentile.map { _ in String(localized: "\(ChildAge.duration(correctedDays)) · from due date") }
            ?? String(localized: "Due in \(ChildAge.duration(-correctedDays))"))
        value(
          title: String(localized: "Actual age"), percentile: actualPercentile,
          age: String(localized: "\(ChildAge.duration(actualDays)) · since birth"))
      }
      Text("The same \(measurementName), with and without adjusting for prematurity.")
        .font(.caption).foregroundStyle(LogStyle.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func value(title: String, percentile: Double?, age: String) -> some View {
    let description = if let percentile {
      WHOWeightForAge.label(for: percentile)
    } else {
      String(localized: "Percentile not available before the due date")
    }
    return VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.subheadline.weight(.semibold))
      if let percentile {
        Text(WHOWeightForAge.rankLabel(for: percentile))
          .font(.title2.weight(.semibold)).monospacedDigit()
          .logValueTransition(value: WHOWeightForAge.label(for: percentile))
        Text("percentile").font(.caption).foregroundStyle(LogStyle.muted)
      } else {
        Text("Not yet").font(.title2.weight(.semibold))
        Text("Before due date").font(.caption).foregroundStyle(LogStyle.muted)
      }
      Text(age).font(.caption).foregroundStyle(LogStyle.muted)
    }
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("WHO \(reference.title), \(title)")
    .accessibilityValue("\(description), \(age)")
  }
}

#if DEBUG
#Preview("Age comparisons · largest text", traits: .fixedLayout(width: 375, height: 1400)) {
  VStack {
    LogCard {
      WeightAgeComparisonView(comparison: .init(
        actual: .init(
          percentile: 19, age: .init(days: 36, chronologicalDays: 36, isCorrected: false),
          reference: .male),
        corrected: .init(
          percentile: 92, age: .init(days: 5, chronologicalDays: 36, isCorrected: true),
          reference: .male), correctedDays: 5))
    }
    Spacer()
  }
  .padding(16).background(LogStyle.canvas).foregroundStyle(LogStyle.ink)
  .dynamicTypeSize(.accessibility5).preferredColorScheme(.light)
}
#endif
