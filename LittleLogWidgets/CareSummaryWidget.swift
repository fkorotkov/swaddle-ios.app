import AppIntents
import SwiftUI
import WidgetKit

struct CareSummaryProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry { CareWidgetPreview.entry }

    func snapshot(for configuration: SelectChildIntent, in context: Context) async -> QuickLogEntry {
        let cache = WidgetCache.read()
        if context.isPreview && configuration.child == nil { return CareWidgetPreview.entry }
        return QuickLogEntry.make(childIdentifier: configuration.child?.id, cache: cache,
            unit: WidgetCache.unit, signingKey: WidgetCache.signingKey, at: .now, source: .homeScreen)
    }

    func timeline(for configuration: SelectChildIntent, in context: Context) async -> Timeline<QuickLogEntry> {
        let now = Date.now
        let cache = WidgetCache.read()
        let unit = WidgetCache.unit
        let key = WidgetCache.signingKey
        let current = QuickLogEntry.make(childIdentifier: configuration.child?.id, cache: cache,
            unit: unit, signingKey: key, at: now, source: .homeScreen)
        let entries = WidgetCareTimeline.dates(child: current.child, pumps: cache?.pumps, from: now).map {
            QuickLogEntry.make(childIdentifier: configuration.child?.id, cache: cache,
                unit: unit, signingKey: key, at: $0, source: .homeScreen)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct CareSummaryWidgetView: View {
    let entry: QuickLogEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.redactionReasons) private var redactionReasons

    private var palette: BabyPalette { .init(gender: entry.child?.gender) }
    private var childName: String {
        redactionReasons.contains(.privacy) ? String(localized: "Your child") :
            entry.child?.name ?? String(localized: "Your child")
    }
    private var large: Bool { family == .systemLarge }
    private var fallback: URL {
        QuickLogControl(action: .bottle, entry: entry).url(host: entry.child == nil ? "family" : "today")
    }
    private var updatedLabel: String {
        entry.asOf.map { String(localized: "As of \($0.formatted(date: .omitted, time: .shortened))") } ?? ""
    }

    var body: some View {
        Group {
            if let child = entry.child {
                overview(WidgetCareSummary(child: child, pumps: entry.pumps, at: entry.date))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "leaf").font(.title2).foregroundStyle(palette.accent).accessibilityHidden(true)
                    Text("Care & quick log").font(.headline)
                    Text("Choose a child in Edit Widget. Open the app if your family has changed.")
                        .font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) { Color(uiColor: .secondarySystemGroupedBackground) }
        .widgetURL(fallback)
    }

    private func overview(_ summary: WidgetCareSummary) -> some View {
        VStack(alignment: .leading, spacing: large ? 12 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(childName).font(.headline).foregroundStyle(accent(palette.accent))
                    .lineLimit(1).privacySensitive().layoutPriority(1)
                Spacer(minLength: 0)
                Text("Last 24 hours").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if let asOf = entry.asOf, entry.date.timeIntervalSince(asOf) > 900 {
                    Image(systemName: "clock").font(.caption2).foregroundStyle(.secondary)
                        .accessibilityLabel(updatedLabel)
                }
            }
            Group {
                if large {
                    VStack(spacing: 8) { metrics(summary) }
                } else {
                    HStack(alignment: .top, spacing: 10) { metrics(summary) }
                }
            }
            .privacySensitive()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Last 24 hours")
            .accessibilityHint(updatedLabel)
            if large { Spacer(minLength: 0) }
            if entry.canRecord || entry.isPreview {
                CareSummaryActionRow(entry: entry, childName: childName, accent: accent(palette.accent),
                                     surface: renderingMode == .fullColor ? palette.surface : Color.primary.opacity(0.12))
            } else {
                Link(destination: fallback) {
                    Label("Open Swaddle to check family access", systemImage: "lock")
                        .font(.caption).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.plain)
            }
            if large {
                HStack {
                    Text("Diapers save now · Bottle opens editor")
                    Spacer(minLength: 0)
                }.font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                if !updatedLabel.isEmpty {
                    Text(updatedLabel).font(.caption2).foregroundStyle(.secondary).privacySensitive()
                }
            }
        }
    }

    @ViewBuilder private func metrics(_ summary: WidgetCareSummary) -> some View {
        Button(intent: SetWidgetVolumeUnitIntent(useOunces: entry.unit == .ml)) {
            CareSummaryMetric(title: "Bottles", symbol: "waterbottle.fill",
                value: entry.unit.quantity(summary.activity.totalML),
                detail: String(localized: "\(summary.activity.bottles) feeds"),
                tint: accent(palette.accent), large: large, showsUnitSwitch: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint(entry.unit == .ml ? String(localized: "Switch volumes to ounces") : String(localized: "Switch volumes to milliliters"))
        CareSummaryMetric(title: "Family pumping", symbol: "drop",
            value: summary.pumpedML.map(entry.unit.quantity) ?? "—",
            detail: summary.pumpingSessions.map { String(localized: "\($0) sessions") } ?? String(localized: "Open Swaddle"),
            tint: accent(BabyPalette.pumpingAccent), large: large)
        CareSummaryMetric(title: "Diapers", symbol: "drop.fill",
            value: summary.activity.changes.formatted(),
            detail: String(localized: "\(summary.activity.wet) wet · \(summary.activity.soiled) soiled"),
            tint: accent(BabyPalette.sage.accent), large: large)
    }

    private func accent(_ color: Color) -> Color { renderingMode == .fullColor ? color : .primary }
}

private struct CareSummaryMetric: View {
    let title: LocalizedStringKey
    let symbol: String
    let value: String
    let detail: String
    let tint: Color
    let large: Bool
    var showsUnitSwitch = false

    var body: some View {
        Group {
            if large {
                HStack(spacing: 12) {
                    Image(systemName: symbol).font(.title3).foregroundStyle(tint)
                        .frame(width: 28).accessibilityHidden(true).widgetAccentable()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                        detailLabel.font(.caption)
                    }
                    Spacer(minLength: 4)
                    valueLabel.font(.system(.title2, design: .rounded, weight: .semibold))
                }
                .padding(12).frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                .background(tint.opacity(0.08), in: .rect(cornerRadius: 18))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                    valueLabel.font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundStyle(tint).widgetAccentable()
                    detailLabel.font(.caption2)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var valueLabel: some View {
        Text(value).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            .contentTransition(.numericText())
    }

    private var detailLabel: some View {
        HStack(spacing: 4) {
            Text(detail)
            if showsUnitSwitch { Text("mL ↔ oz").accessibilityHidden(true) }
        }
        .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.65)
    }
}

private struct CareSummaryActionRow: View {
    let entry: QuickLogEntry
    let childName: String
    let accent: Color
    let surface: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WidgetQuickAction.allCases, id: \.self) { action in
                let control = QuickLogControl(action: action, entry: entry)
                Link(destination: control.destination) {
                    VStack(spacing: 3) {
                        QuickLogSymbol(action: action, status: control.statusSymbol)
                            .font(.caption).widgetAccentable()
                        Text(control.title).font(.caption2.weight(.semibold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(accent)
                    .background(surface, in: .rect(cornerRadius: 14))
                    .contentShape(.rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(control.accessibilityLabel(child: childName))
                .accessibilityHint(control.accessibilityHint)
            }
        }
    }
}

struct CareSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SwaddleCareSummary", intent: SelectChildIntent.self,
                               provider: CareSummaryProvider()) { entry in
            CareSummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Care & quick log")
        .description("Last 24 hours of bottles, family pumping, and diapers, with Pee, Poo, Both, and Bottle actions.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

/// Fictional data for the widget gallery and native previews only.
enum CareWidgetPreview {
    static var entry: QuickLogEntry {
        let now = Date.now
        let family = UUID()
        let childID = UUID()
        let actor = UUID()
        let bottles = (0..<8).map { offset in
            Activity(familyID: family, childID: childID, occurredAt: now.addingTimeInterval(-Double(offset + 1) * 7200),
                authorID: actor, payload: .bottle(.init(milkML: 105, formulaML: 15, unit: .ml)))
        }
        let diapers = (0..<7).map { offset in
            Activity(familyID: family, childID: childID, occurredAt: now.addingTimeInterval(-Double(offset + 1) * 9000),
                authorID: actor, payload: .diaper(.init(pee: true, poo: offset < 4)))
        }
        return QuickLogEntry(date: now,
            child: CachedChild(id: childID, familyID: family, name: "Robin", activities: bottles + diapers, gender: .boy),
            canRecord: true, isPreview: true, asOf: now, unit: .oz,
            pumps: [CachedPumpSession(id: UUID(), familyID: family, occurredAt: now.addingTimeInterval(-3600), totalML: 270),
                    CachedPumpSession(id: UUID(), familyID: family, occurredAt: now.addingTimeInterval(-18000), totalML: 240)])
    }
}

#Preview("Care and actions", as: .systemMedium) { CareSummaryWidget() } timeline: {
    CareWidgetPreview.entry
}
#Preview("Large care and actions", as: .systemLarge) { CareSummaryWidget() } timeline: {
    CareWidgetPreview.entry
}
#Preview("Choose a child", as: .systemMedium) { CareSummaryWidget() } timeline: {
    QuickLogEntry(date: .now, canRecord: false)
}
