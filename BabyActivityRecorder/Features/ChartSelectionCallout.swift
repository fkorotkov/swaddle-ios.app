import Charts
import SwiftUI

struct ChartSelectionCallout: View {
  let date: Date
  let value: String
  let detail: String
  var includesTime = false
  @Binding var selection: Date?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 4) {
          Text(date, format: .dateTime.month(.abbreviated).day().year())
            .font(.caption.weight(.semibold)).foregroundStyle(LogStyle.muted)
          if includesTime {
            Text(date, format: .dateTime.hour().minute())
              .font(.caption).foregroundStyle(LogStyle.muted)
          }
        }
        Spacer(minLength: 0)
        Button("Dismiss chart details", systemImage: "xmark") {
          selection = nil
        }
        .labelStyle(.iconOnly).font(.body.weight(.semibold))
        .foregroundStyle(LogStyle.muted)
        .frame(width: 44, height: 44).contentShape(.circle)
        .background(.primary.opacity(0.06), in: .circle)
        .buttonStyle(.plain)
        .accessibilityIdentifier("chart.details.dismiss")
      }
      Text(value).font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
        .logValueTransition(value: value)
      if !detail.isEmpty {
        Text(detail).font(.caption).foregroundStyle(LogStyle.muted).lineLimit(3)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .foregroundStyle(LogStyle.ink)
    .accessibilityElement(children: .contain)
    .accessibilityAction(.escape) { selection = nil }
  }
}

extension View {
  /// Keep precise values beneath the plot, in a space reserved before selection.
  func chartSelectionDetails(
    date: Date?, value: String, detail: String, includesTime: Bool = false,
    selection: Binding<Date?>
  ) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      self
      ChartSelectionReadout(date: date, value: value, detail: detail,
                            includesTime: includesTime, selection: selection)
    }
  }

  /// A tap leaves the value visible; vertical swipes still scroll the screen.
  @ViewBuilder
  func chartDateSelection(_ selection: Binding<Date?>, vertical: Bool = false, byDay: Bool = true) -> some View {
    if vertical {
      modifier(ChartDaySelection(selection: selection, vertical: true, byDay: byDay))
    } else {
      modifier(ChartDaySelection(selection: selection, vertical: false, byDay: byDay))
    }
  }
}

private struct ChartSelectionReadout: View {
  let date: Date?
  let value: String
  let detail: String
  let includesTime: Bool
  @Binding var selection: Date?
  @ScaledMetric(relativeTo: .subheadline) private var reservedHeight = 156
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Divider().padding(.bottom, 8)
      if let date {
        ChartSelectionCallout(date: date, value: value, detail: detail,
                              includesTime: includesTime, selection: $selection)
        .transition(.opacity)
      } else {
        Label(includesTime ? String(localized: "Tap a measurement for exact values") : String(localized: "Tap a day for exact values"), systemImage: "hand.tap")
          .font(.subheadline).foregroundStyle(LogStyle.muted)
          .padding(.top, 16)
        .transition(.opacity)
      }
      Spacer(minLength: 0)
    }.frame(height: reservedHeight, alignment: .topLeading)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: date != nil)
      .sensoryFeedback(.selection, trigger: date) { _, new in new != nil }
  }
}

private struct ChartDaySelection: ViewModifier {
  @Binding var selection: Date?
  let vertical: Bool
  let byDay: Bool
  @Environment(\.calendar) private var calendar
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    Group {
      if vertical { content.chartYSelection(value: $selection) }
      else { content.chartXSelection(value: $selection) }
    }.chartGesture { proxy in
      SpatialTapGesture().onEnded { event in
        let date: Date? = vertical
          ? proxy.value(atY: event.location.y, as: Date.self)
          : proxy.value(atX: event.location.x, as: Date.self)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
          if byDay, let date, let selection, calendar.isDate(date, inSameDayAs: selection) {
            self.selection = nil
          } else if vertical { proxy.selectYValue(at: event.location.y) }
          else { proxy.selectXValue(at: event.location.x) }
        }
      }
    }
  }
}
