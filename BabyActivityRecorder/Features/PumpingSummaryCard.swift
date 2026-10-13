import SwiftUI

struct PumpingSummaryCard: View {
  let summary: PumpingSummary
  let unit: VolumeUnit

  var body: some View {
    LogCard(color: LogStyle.apricot, verticalPadding: 16) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) {
          heading.fixedSize()
          Spacer(minLength: 0)
          amount.fixedSize()
          chevron
        }
        VStack(alignment: .leading, spacing: 8) {
          heading
          HStack(alignment: .firstTextBaseline) {
            amount
            Spacer(minLength: 8)
            chevron
          }
        }
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: 5) {
      Label("Your pumping", systemImage: "drop.halffull")
        .font(.subheadline.weight(.semibold))
      Text(summary.sessions == 0 ? String(localized: "No sessions recorded") : String(localized: "\(summary.sessions) sessions"))
      .font(.caption).foregroundStyle(LogStyle.muted)
    }
  }

  private var amount: some View {
    Text(unit.quantity(summary.totalML))
      .font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
      .logValueTransition(value: summary.totalML)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var chevron: some View {
    Image(systemName: "chevron.forward").font(.caption.weight(.semibold))
      .foregroundStyle(LogStyle.muted).accessibilityHidden(true)
  }
}
