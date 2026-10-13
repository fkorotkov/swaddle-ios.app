import WidgetKit
import AppIntents
import SwiftUI

struct ActivityEntry: TimelineEntry {
    let date: Date
    let asOf: Date?
    let child: CachedChild?
    let unit: VolumeUnit
}
struct ActivityProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ActivityEntry { ActivityEntry(date: .now, asOf: nil, child: nil, unit: .ml) }
    func snapshot(for configuration: SelectChildIntent, in context: Context) async -> ActivityEntry { entry(configuration, at: .now) }
    func timeline(for configuration: SelectChildIntent, in context: Context) async -> Timeline<ActivityEntry> {
        let now = Date.now
        // Recalculate elapsed-window totals even without opening the app.
        let entries = (0...12).map { entry(configuration, at: now.addingTimeInterval(Double($0) * 300)) }
        return Timeline(entries: entries, policy: .atEnd)
    }
    private func entry(_ configuration: SelectChildIntent, at date: Date) -> ActivityEntry {
        let snapshot = WidgetCache.read()
        let target = snapshot?.children.first { "\($0.familyID.uuidString)/\($0.id.uuidString)" == configuration.child?.id }
        // A removed or unspecified target never falls back to a sibling.
        return ActivityEntry(date: date, asOf: snapshot?.asOf, child: target, unit: WidgetCache.unit)
    }
}
struct LittleLogWidgetView: View {
    let entry: ActivityEntry
    @Environment(\.widgetFamily) private var family
    private var palette: BabyPalette { BabyPalette(gender: entry.child?.gender) }
    private var summary: ActivitySummary { ActivitySummary(activities: entry.child?.activities ?? [], childID: entry.child?.id, start: entry.date.addingTimeInterval(-86400), end: entry.date) }
    var body: some View {
        Group {
            if let child = entry.child {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 12) {
                    HStack {
                        Text(child.name).font(.headline).foregroundStyle(palette.accent)
                        Spacer()
                        Image(systemName: "leaf.fill").foregroundStyle(palette.accent).accessibilityHidden(true)
                    }
                    Text("Last 24 hours").font(.caption).foregroundStyle(.secondary)
                    if family == .systemSmall { compactVolumes }
                    else {
                        HStack(alignment: .top, spacing: 20) {
                            volumeButton
                            Divider()
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(summary.wet) wet · \(summary.soiled) soiled").font(.subheadline.bold())
                                Text("\(summary.peeOnly) pee · \(summary.pooOnly) poo · \(summary.both) both").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if family == .systemLarge {
                        Divider()
                        Text("Recent moments").font(.subheadline.bold())
                        ForEach(child.activities.filter { $0.payload.isComplete }.prefix(3)) { activity in
                            HStack {
                                Image(systemName: activity.payload.kind.symbol)
                                Text(recentTitle(activity)).font(.caption)
                                Spacer()
                                Text(activity.occurredAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        if summary.nursingSessions > 0 { Text("\(summary.nursingSessions) breastfeeds · \(Int(summary.nursingSeconds / 60)) min").font(.caption) }
                        Spacer(minLength: 0)
                    }
                    if let asOf = entry.asOf, family != .systemSmall {
                        Text("As of \(asOf.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
                    }
                }.privacySensitive()
                    .widgetURL(URL(string: "littlelog://today?family=\(child.familyID.uuidString)&child=\(child.id.uuidString)"))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "leaf").font(.title2)
                    Text("Swaddle").font(.headline)
                    Text("Choose a child in Edit Widget. Open the app if your family has changed.").font(.caption).foregroundStyle(.secondary)
                }.widgetURL(URL(string: "littlelog://family"))
            }
        }
        .containerBackground(for: .widget) { entry.child?.gender == nil ? Color(uiColor: .secondarySystemGroupedBackground) : palette.surface }
    }
    private var compactVolumes: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(intent: SetWidgetVolumeUnitIntent(useOunces: entry.unit == .ml)) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.unit.string(summary.totalML)).font(.title2.bold()).monospacedDigit()
                    Text(entry.unit.label).font(.caption)
                    Image(systemName: "arrow.left.arrow.right").font(.caption2)
                }
            }.buttonStyle(.plain).accessibilityLabel(entry.unit == .ml ? String(localized: "Switch volumes to ounces") : String(localized: "Switch volumes to milliliters"))
            Text("\(summary.wet) wet · \(summary.soiled) soiled").font(.caption.bold())
        }
    }
    private var volumeButton: some View {
        Button(intent: SetWidgetVolumeUnitIntent(useOunces: entry.unit == .ml)) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.unit.quantity(summary.totalML)).font(.title3.bold()).monospacedDigit()
                Text("\(entry.unit.string(summary.milkML)) milk · \(entry.unit.string(summary.formulaML)) formula").font(.caption2)
                if summary.unknownML > 0 {
                    Text("\(entry.unit.string(summary.unknownML)) split not recorded").font(.caption2)
                } else { Text("mL ↔ oz").font(.caption2).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }.buttonStyle(.plain).accessibilityLabel(entry.unit == .ml ? String(localized: "Switch volumes to ounces") : String(localized: "Switch volumes to milliliters"))
    }
    private func recentTitle(_ activity: Activity) -> String {
        switch activity.payload {
        case .bottle(let bottle): String(localized: "Bottle · \(entry.unit.quantity(bottle.totalML))")
        case .diaper(let diaper): diaper.title
        case .nursing: String(localized: "Breastfeeding")
        case .weight: String(localized: "Weight recorded")
        case .length: String(localized: "Length / height recorded")
        case .headCircumference: String(localized: "Head circumference recorded")
        case .temperature: String(localized: "Temperature recorded")
        case .careNote: String(localized: "Care note")
        }
    }
}
struct LittleLogWidgets: Widget {
    let kind = "LittleLogActivity"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectChildIntent.self, provider: ActivityProvider()) { entry in
            LittleLogWidgetView(entry: entry)
        }
        .configurationDisplayName("A little overview")
        .description("A child’s last 24 hours. Tap volume to switch mL and ounces.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
